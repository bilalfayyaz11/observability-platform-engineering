#!/usr/bin/env bash

set -euo pipefail

readonly ACTIVE_CONFIG="/etc/nginx/sites-available/blue-green"
readonly ENABLED_CONFIG="/etc/nginx/sites-enabled/blue-green"
readonly STATE_DIR="/var/lib/blue-green-deployment"
readonly STATE_FILE="$STATE_DIR/active-environment"
readonly LOG_FILE="/var/log/blue-green-deployment.log"
readonly LOCK_FILE="/tmp/blue-green-deployment.lock"

usage() {
    echo "Usage: $0 blue|green"
}

log() {
    local message="$1"

    printf '%s %s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$message" |
    sudo tee -a "$LOG_FILE" >/dev/null

    echo "$message"
}

load_environment() {
    local environment="$1"

    case "$environment" in
        blue)
            PORT="8080"
            VERSION="1.0"
            PAGE_MARKER="Application Version 1.0 - BLUE"
            ;;
        green)
            PORT="8081"
            VERSION="2.0"
            PAGE_MARKER="Application Version 2.0 - GREEN"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

validate_candidate() {
    local environment="$1"
    local port="$2"
    local version="$3"
    local page_marker="$4"

    log "Validating candidate: $environment version $version"

    local health_response
    local page_response

    health_response=$(
        curl \
            --noproxy '*' \
            --fail \
            --silent \
            --show-error \
            --retry 5 \
            --retry-delay 1 \
            --connect-timeout 2 \
            --max-time 5 \
            "http://127.0.0.1:${port}/health"
    )

    grep -q "environment=${environment}" <<< "$health_response"
    grep -q "version=${version}" <<< "$health_response"
    grep -q "status=healthy" <<< "$health_response"

    page_response=$(
        curl \
            --noproxy '*' \
            --fail \
            --silent \
            --show-error \
            --retry 5 \
            --retry-delay 1 \
            --connect-timeout 2 \
            --max-time 5 \
            "http://127.0.0.1:${port}/"
    )

    grep -q "$page_marker" <<< "$page_response"

    log "Candidate validation passed: $environment version $version"
}

generate_configuration() {
    local port="$1"
    local destination="$2"

    cat > "$destination" << NGINX_EOF
upstream blue_green_backend {
    server 127.0.0.1:${port};
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name localhost;

    location = /health {
        proxy_pass http://blue_green_backend/health;
        proxy_set_header Host \$host;
        proxy_connect_timeout 2s;
        proxy_read_timeout 3s;
        access_log off;
    }

    location / {
        proxy_pass http://blue_green_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 3s;
        proxy_read_timeout 10s;
    }
}
NGINX_EOF
}

verify_production() {
    local environment="$1"
    local version="$2"
    local page_marker="$3"

    local attempt
    local health_response
    local page_response

    for attempt in $(seq 1 30); do
        health_response=$(
            curl \
                --noproxy '*' \
                --silent \
                --show-error \
                --connect-timeout 2 \
                --max-time 5 \
                http://127.0.0.1/health \
                2>/dev/null || true
        )

        page_response=$(
            curl \
                --noproxy '*' \
                --silent \
                --show-error \
                --connect-timeout 2 \
                --max-time 5 \
                http://127.0.0.1/ \
                2>/dev/null || true
        )

        if grep -q "environment=${environment}" <<< "$health_response" &&
           grep -q "version=${version}" <<< "$health_response" &&
           grep -q "status=healthy" <<< "$health_response" &&
           grep -q "$page_marker" <<< "$page_response"
        then
            log "Production verification passed on attempt $attempt"
            return 0
        fi

        current_environment=$(
            awk -F= '/^environment=/ {print $2}' <<< "$health_response"
        )

        current_version=$(
            awk -F= '/^version=/ {print $2}' <<< "$health_response"
        )

        log "Waiting for new Nginx workers: attempt $attempt, observed environment=${current_environment:-unknown}, version=${current_version:-unknown}"
        sleep 0.5
    done

    log "Production did not converge to $environment version $version"
    return 1
}

main() {
    if [[ "$#" -ne 1 ]]; then
        usage
        exit 1
    fi

    local target_environment="$1"
    load_environment "$target_environment"

    sudo mkdir -p "$STATE_DIR"
    sudo touch "$LOG_FILE"

    exec 9>"$LOCK_FILE"

    if ! flock -n 9; then
        echo "Another deployment switch is already running."
        exit 1
    fi

    local candidate_config
    local backup_config

    candidate_config=$(mktemp /tmp/blue-green-candidate.XXXXXX)
    backup_config=$(mktemp /tmp/blue-green-backup.XXXXXX)

    trap "rm -f -- '$candidate_config' '$backup_config'" EXIT

    validate_candidate \
        "$target_environment" \
        "$PORT" \
        "$VERSION" \
        "$PAGE_MARKER"

    generate_configuration "$PORT" "$candidate_config"

    if [[ -s "$ACTIVE_CONFIG" ]]; then
        sudo cp "$ACTIVE_CONFIG" "$backup_config"
    else
        : > "$backup_config"
    fi

    sudo cp "$candidate_config" "$ACTIVE_CONFIG"
    sudo ln -sfn "$ACTIVE_CONFIG" "$ENABLED_CONFIG"

    if ! sudo nginx -t; then
        log "Nginx validation failed; restoring previous configuration"

        if [[ -s "$backup_config" ]]; then
            sudo cp "$backup_config" "$ACTIVE_CONFIG"
            sudo nginx -t
        fi

        exit 1
    fi

    log "Reloading Nginx for $target_environment version $VERSION"
    sudo systemctl reload nginx

    if verify_production \
        "$target_environment" \
        "$VERSION" \
        "$PAGE_MARKER"
    then
        printf '%s\n' "$target_environment" |
            sudo tee "$STATE_FILE" >/dev/null

        log "Deployment completed: $target_environment version $VERSION is active"
        exit 0
    fi

    log "Post-switch validation failed; restoring previous configuration"

    if [[ -s "$backup_config" ]]; then
        sudo cp "$backup_config" "$ACTIVE_CONFIG"
        sudo nginx -t
        sudo systemctl reload nginx
    fi

    log "Rollback completed after failed deployment"
    exit 1
}

main "$@"
