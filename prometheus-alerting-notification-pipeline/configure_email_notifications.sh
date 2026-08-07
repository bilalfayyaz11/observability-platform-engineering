#!/usr/bin/env bash
set -euo pipefail

ALERTMANAGER_CONFIG="/etc/alertmanager/alertmanager.yml"
BACKUP_CONFIG="/etc/alertmanager/alertmanager.webhook-only.yml"

echo "===== BACK UP WORKING WEBHOOK CONFIGURATION ====="

sudo cp \
  "$ALERTMANAGER_CONFIG" \
  "$BACKUP_CONFIG"

sudo chown root:root "$BACKUP_CONFIG"
sudo chmod 0600 "$BACKUP_CONFIG"

echo "Backup created:"
sudo ls -l "$BACKUP_CONFIG"

echo "===== CREATE SECURE SMTP CONFIGURATION TEMPLATE ====="

cat > smtp-settings.example <<'SMTP'
SMTP_SMARTHOST=smtp.gmail.com:587
SMTP_FROM=your-email@gmail.com
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-google-app-password
SMTP_RECIPIENT=recipient@example.com
SMTP

chmod 0600 smtp-settings.example

echo "===== CREATE CONFIGURATION GENERATOR ====="

cat > generate_alertmanager_email_config.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${1:-}"

if [[ -z "$SETTINGS_FILE" ]]; then
    echo "Usage:"
    echo "  $0 /path/to/smtp-settings"
    exit 2
fi

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "ERROR: SMTP settings file not found"
    exit 1
fi

FILE_MODE="$(stat -c '%a' "$SETTINGS_FILE")"

if [[ "$FILE_MODE" != "600" ]]; then
    echo "ERROR: SMTP settings must have permission 0600"
    echo "Current permissions: ${FILE_MODE}"
    exit 1
fi

set -a
source "$SETTINGS_FILE"
set +a

required_variables=(
    SMTP_SMARTHOST
    SMTP_FROM
    SMTP_USERNAME
    SMTP_PASSWORD
    SMTP_RECIPIENT
)

for variable in "${required_variables[@]}"; do
    if [[ -z "${!variable:-}" ]]; then
        echo "ERROR: Missing ${variable}"
        exit 1
    fi
done

escape_yaml_single_quote() {
    sed "s/'/''/g" <<<"$1"
}

SMTP_SMARTHOST_ESCAPED="$(
  escape_yaml_single_quote "$SMTP_SMARTHOST"
)"

SMTP_FROM_ESCAPED="$(
  escape_yaml_single_quote "$SMTP_FROM"
)"

SMTP_USERNAME_ESCAPED="$(
  escape_yaml_single_quote "$SMTP_USERNAME"
)"

SMTP_PASSWORD_ESCAPED="$(
  escape_yaml_single_quote "$SMTP_PASSWORD"
)"

SMTP_RECIPIENT_ESCAPED="$(
  escape_yaml_single_quote "$SMTP_RECIPIENT"
)"

TEMP_CONFIG="$(mktemp)"

trap 'rm -f "$TEMP_CONFIG"' EXIT

cat > "$TEMP_CONFIG" <<EOF
global:
  smtp_smarthost: '${SMTP_SMARTHOST_ESCAPED}'
  smtp_from: '${SMTP_FROM_ESCAPED}'
  smtp_auth_username: '${SMTP_USERNAME_ESCAPED}'
  smtp_auth_password: '${SMTP_PASSWORD_ESCAPED}'
  smtp_require_tls: true

route:
  receiver: multi-channel
  group_by:
    - alertname
    - instance
  group_wait: 10s
  group_interval: 30s
  repeat_interval: 1h

receivers:
  - name: multi-channel

    email_configs:
      - to: '${SMTP_RECIPIENT_ESCAPED}'
        send_resolved: true
        subject: 'Prometheus Alert: {{ .GroupLabels.alertname }}'
        html: |
          <h3>{{ .Status | toUpper }}: {{ .GroupLabels.alertname }}</h3>
          {{ range .Alerts }}
          <p><strong>Summary:</strong> {{ .Annotations.summary }}</p>
          <p><strong>Description:</strong> {{ .Annotations.description }}</p>
          <p><strong>Severity:</strong> {{ .Labels.severity }}</p>
          <p><strong>Instance:</strong> {{ .Labels.instance }}</p>
          {{ end }}

    webhook_configs:
      - url: http://127.0.0.1:8080/alerts
        send_resolved: true
