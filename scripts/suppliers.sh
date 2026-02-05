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
  if [[ -z "$qs" ]]; then qs=""; fi
  pos_request GET "/shops/$SHOP_ID/supplier${qs}"
  ;;
purchases)
  qs="${1:-}"; shift || true
  if [[ -z "$qs" ]]; then qs="?page=1&page_size=30"; fi
  pos_request GET "/shops/$SHOP_ID/purchases${qs}"
  ;;
update-purchase)
  confirm_write
  purchase_id="${1:?PURCHASE_ID required}"
  shift || true
  body="$(cat)"
  pos_request PUT "/shops/$SHOP_ID/purchases/$purchase_id" "$body"
  ;;
split-purchase)
  confirm_write
  body="$(cat)"
  pos_request POST "/shops/$SHOP_ID/purchases/separate" "$body"
  ;;
help|--help|-h)
  cat <<EOF
Usage: suppliers.sh <command> [args]

Commands:
  list [query]              List suppliers
  purchases [query]         List purchase orders
  update-purchase <id>      Update a purchase order (reads JSON from stdin)
  split-purchase            Split a purchase order (reads JSON from stdin)

Examples:
  # List all suppliers
  bash suppliers.sh list

  # List suppliers with pagination
  bash suppliers.sh list "?page=1&page_size=50"

  # List purchase orders
  bash suppliers.sh purchases

  # Filter purchases by status (1 = imported)
  bash suppliers.sh purchases "?status=1"

  # Filter purchases by status (-1 = new, 0 = confirmed, 2 = cancelled)
  bash suppliers.sh purchases "?status=-1"

  # Update a purchase order
  export CONFIRM_WRITE=YES
  cat <<'JSON' | bash suppliers.sh update-purchase "fb056b32-9cf6-4c5a-92de-0eb94db71121"
  {
    "purchase": {
      "status": 1,
      "warehouse_id": "c52e67ad-d9d0-4276-abe4-e0c9f1f7d2da",
      "note": "Updated note",
      "items": [
        {
          "variation_id": "29044dcf-2f4c-492f-a0a9-e447b20e21da",
          "quantity": 10,
          "imported_price": 100000
        }
      ]
    }
  }
  JSON

  # Split a purchase order
  export CONFIRM_WRITE=YES
  cat split-payload.json | bash suppliers.sh split-purchase

Query Parameters:
  list:
    page, page_size      Pagination

  purchases:
    page, page_size      Pagination
    status               -2 (all), -1 (new), 0 (confirmed), 1 (imported), 2 (cancelled)
    type                 Type filter (default: "product")
    get_time_import      Include import time (boolean)

Purchase Status Codes:
  -1  Mới (New)
   0  Đã xác nhận (Confirmed)
   1  Đã nhập hàng (Imported)
   2  Đã hủy (Cancelled)

Environment:
  POS_API_KEY      API key (required)
  SHOP_ID          Shop ID (required)
  CONFIRM_WRITE    Set to YES for write operations
  POS_BASE_URL     API base URL (default: https://pos.pages.fm/api/v1)
EOF
  ;;
*)
  echo "Unknown command: $cmd" >&2
  echo "Run 'suppliers.sh help' for usage" >&2
  exit 1
  ;;
esac
