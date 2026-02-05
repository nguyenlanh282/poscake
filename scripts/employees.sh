#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$DIR/common.sh"

require_env SHOP_ID

cmd="${1:-}"
shift || true

case "$cmd" in
list)
  qs="${1:-}"; shift || true
  pos_request GET "/shops/$SHOP_ID/users${qs}"
  ;;
help|--help|-h)
  cat <<EOF
Usage: employees.sh <command> [args]

Commands:
  list              List all employees in the shop

Examples:
  # List all employees
  bash employees.sh list

  # Filter employees by department (using jq)
  bash employees.sh list | jq '.data[] | select(.department.name == "Sales")'

  # Find employee by name
  bash employees.sh list | jq '.data[] | select(.user.name | contains("Hoang"))'

  # Get all employee emails
  bash employees.sh list | jq -r '.data[].user.email'

  # Get employees in a specific sale group
  bash employees.sh list | jq '.data[] | select(.sale_group.name == "Ca sáng")'

  # Count employees by department
  bash employees.sh list | jq '[.data[] | .department.name] | group_by(.) | map({department: .[0], count: length})'

Response Structure:
  Each employee has:
    - user_id          Employee UUID
    - user.name        Employee name
    - user.email       Employee email
    - user.phone_number  Phone number (may be null)
    - user.fb_id       Facebook ID if logged in via FB
    - department.id    Department ID
    - department.name  Department name (e.g., "Sales", "Support")
    - sale_group.id    Sale group ID
    - sale_group.name  Sale group name (e.g., "Ca sáng", "Nhóm A")

Environment:
  POS_API_KEY    API key (required)
  SHOP_ID        Shop ID (required)
  POS_BASE_URL   API base URL (default: https://pos.pages.fm/api/v1)
EOF
  ;;
*)
  echo "Unknown command: $cmd" >&2
  echo "Run 'employees.sh help' for usage" >&2
  exit 1
  ;;
esac
