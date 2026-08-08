#!/usr/bin/env bash

set -u

if [ ! -f "$HOME/grafana-admin.env" ]; then
  echo "Missing ~/grafana-admin.env"
  exit 1
fi

source "$HOME/grafana-admin.env"

BASE_URL="http://127.0.0.1:3000"

echo "Grafana Access Review - $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "=========================================================="
echo

echo "Organization Users"
echo "------------------"

curl -fsS \
  -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  "$BASE_URL/api/org/users" \
  | jq -r '
      .[]
      | [
          .login,
          .email,
          .role
        ]
      | @tsv
    '

echo
echo "Teams"
echo "-----"

curl -fsS \
  -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  "$BASE_URL/api/teams/search?perpage=100&page=1" \
  | jq -r '
      .teams[]
      | [
          .id,
          .name,
          .memberCount
        ]
      | @tsv
    '

echo
echo "Folders"
echo "-------"

curl -fsS \
  -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  "$BASE_URL/api/search?type=dash-folder&limit=100" \
  | jq -r '
      .[]
      | [
          .uid,
          .title
        ]
      | @tsv
    '

echo
echo "Service Accounts"
echo "----------------"

curl -fsS \
  -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" \
  "$BASE_URL/api/serviceaccounts/search?perpage=100&page=1" \
  | jq -r '
      .serviceAccounts[]
      | [
          .id,
          .name,
          .role,
          .isDisabled
        ]
      | @tsv
    '
