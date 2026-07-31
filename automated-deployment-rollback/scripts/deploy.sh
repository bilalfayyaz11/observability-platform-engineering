#!/usr/bin/env bash

set -euo pipefail

readonly WORK_DIR="$HOME/deployment-recovery"
readonly APP_DIR="$WORK_DIR/app"
readonly BACKUP_DIR="$WORK_DIR/backups"
readonly RELEASE_DIR="$WORK_DIR/releases"
readonly STATE_DIR="$WORK_DIR/state"
readonly LOG_DIR="$WORK_DIR/logs"
readonly DEPLOY_DIR="/var/www/html"
readonly STATE_FILE="$STATE_DIR/active-version"
readonly AUDIT_LOG="$LOG_DIR/deployment-audit.log"
readonly LOCK_FILE="/tmp/deployment-recovery.lock"

log_event() {
    local event_type="$1"
    local message="$2"

    printf '[%s] %s: %s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$event_type" \
        "$message" |
    tee -a "$AUDIT_LOG"
}

verify_http() {
    local expected_version="$1"
    local expected_status="$2"

    local response
    local http_code

    http_code=$(
        curl \
            --noproxy '*' \
            --silent \
            --output /dev/null \
            --write-out '%{http_code}' \
            --connect-timeout 3 \
            --max-time 5 \
            http://127.0.0.1/
    )

    [[ "$http_code" == "200" ]] || return 1

    response=$(
        curl \
            --noproxy '*' \
            --fail \
            --silent \
            --show-error \
            --connect-timeout 3 \
            --max-time 5 \
            http://127.0.0.1/
    )

    grep -q "Application Version ${expected_version}" <<< "$response"
    grep -q "Status: ${expected_status}" <<< "$response"
}

create_backup() {
    local active_version="unknown"
    local timestamp
    local backup_path

    if [[ -s "$STATE_FILE" ]]; then
        active_version=$(cat "$STATE_FILE")
    fi

    timestamp=$(date -u +'%Y%m%dT%H%M%SZ')
    backup_path="$BACKUP_DIR/${timestamp}_${active_version}"

    mkdir -p "$backup_path"

    if [[ -d "$DEPLOY_DIR" ]]; then
        sudo rsync \
            --archive \
            --delete \
            "$DEPLOY_DIR/" \
            "$backup_path/"
    fi

    printf '%s\n' "$active_version" > "$backup_path/version"
    sha256sum "$backup_path/index.html" > "$backup_path/index.html.sha256" 2>/dev/null || true

    echo "$backup_path"
}

stage_release() {
    local version="$1"
    local stage_path="$RELEASE_DIR/$version"

    rm -rf "$stage_path"
    mkdir -p "$stage_path"

    git -C "$APP_DIR" archive "$version" |
        tar -x -C "$stage_path"

    [[ -s "$stage_path/index.html" ]]
    [[ -s "$stage_path/release.env" ]]

    echo "$stage_path"
}

deploy_release() {
    local version="$1"
    local stage_path
    local backup_path
    local app_version
    local release_status

    git -C "$APP_DIR" rev-parse --verify "$version^{commit}" >/dev/null

    stage_path=$(stage_release "$version")

    # shellcheck disable=SC1090
    source "$stage_path/release.env"

    app_version="$APP_VERSION"
    release_status="$RELEASE_STATUS"

    backup_path=$(create_backup)
    log_event "BACKUP" "Created $(basename "$backup_path")"

    sudo rsync \
        --archive \
        --delete \
        --exclude 'version' \
        --exclude '*.sha256' \
        "$stage_path/" \
        "$DEPLOY_DIR/"

    sudo nginx -t
    sudo systemctl reload nginx

    if [[ "$release_status" == "broken" ]]; then
        log_event "DEPLOY_FAILURE" "$version contains a simulated release failure"
        rollback_to "$backup_path"
        return 1
    fi

    if ! verify_http "$app_version" "Stable Release"; then
        log_event "DEPLOY_FAILURE" "$version failed production verification"
        rollback_to "$backup_path"
        return 1
    fi

    printf '%s\n' "$version" > "$STATE_FILE"
    log_event "DEPLOY_SUCCESS" "$version is active"
}

rollback_to() {
    local backup_path="$1"
    local restored_version="unknown"

    [[ -d "$backup_path" ]] || {
        log_event "ROLLBACK_FAILURE" "Backup not found: $backup_path"
        return 1
    }

    if [[ -s "$backup_path/version" ]]; then
        restored_version=$(cat "$backup_path/version")
    fi

    if [[ -s "$backup_path/index.html.sha256" ]]; then
        (
            cd "$backup_path"
            sha256sum --check index.html.sha256
        )
    fi

    sudo rsync \
        --archive \
        --delete \
        --exclude 'version' \
        --exclude '*.sha256' \
        "$backup_path/" \
        "$DEPLOY_DIR/"

    sudo nginx -t
    sudo systemctl reload nginx

    printf '%s\n' "$restored_version" > "$STATE_FILE"

    log_event "ROLLBACK_SUCCESS" "Restored $restored_version from $(basename "$backup_path")"
}

rollback_latest() {
    local latest_backup

    latest_backup=$(
        find "$BACKUP_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf '%T@ %p\n' |
        sort -nr |
        awk 'NR == 1 {print $2}'
    )

    [[ -n "$latest_backup" ]] || {
        log_event "ROLLBACK_FAILURE" "No backups available"
        return 1
    }

    rollback_to "$latest_backup"
}

verify_deployment() {
    local active_version="unknown"
    local response

    systemctl is-active --quiet nginx || {
        echo "FAIL: Nginx is not running"
        return 1
    }

    if [[ -s "$STATE_FILE" ]]; then
        active_version=$(cat "$STATE_FILE")
    fi

    response=$(
        curl \
            --noproxy '*' \
            --fail \
            --silent \
            --show-error \
            http://127.0.0.1/
    )

    echo "PASS: Nginx is running"
    echo "PASS: HTTP response is 200"
    echo "Active version: $active_version"
    grep -o 'Application Version [0-9.]*' <<< "$response" | head -n 1
}

main() {
    mkdir -p \
        "$BACKUP_DIR" \
        "$RELEASE_DIR" \
        "$STATE_DIR" \
        "$LOG_DIR"

    exec 9>"$LOCK_FILE"

    flock -n 9 || {
        echo "Another deployment operation is already running"
        exit 1
    }

    case "${1:-}" in
        deploy)
            [[ -n "${2:-}" ]] || {
                echo "Usage: $0 deploy <git-tag>"
                exit 1
            }

            deploy_release "$2"
            ;;
        rollback)
            rollback_latest
            ;;
        verify)
            verify_deployment
            ;;
        *)
            echo "Usage: $0 {deploy <git-tag>|rollback|verify}"
            exit 1
            ;;
    esac
}

main "$@"
