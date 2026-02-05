# Purchase Orders (Phiếu nhập kho)

API endpoints để quản lý phiếu nhập kho từ nhà cung cấp.

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/shops/{SHOP_ID}/purchases` | GET | Danh sách phiếu nhập kho |
| `/shops/{SHOP_ID}/purchases/{PURCHASE_ID}` | PUT | Cập nhật phiếu nhập kho |
| `/shops/{SHOP_ID}/purchases/separate` | POST | Tách phiếu nhập kho |

## GET /purchases - Danh sách phiếu nhập

### Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `page` | integer | No | 1 | Số trang |
| `page_size` | integer | No | 30 | Kích thước trang |
| `status` | integer | No | -2 | Trạng thái lọc |
| `type` | string | No | "product" | Loại phiếu |
| `get_time_import` | boolean | No | false | Lấy thời gian nhập hàng |

### Status Values

| Status | Tên | Mô tả |
|--------|-----|-------|
| -2 | Tất cả | Không lọc trạng thái |
| -1 | Mới | Phiếu vừa tạo |
| 0 | Đã xác nhận | Đã xác nhận với NCC |
| 1 | Đã nhập hàng | Hàng đã về kho |
| 2 | Đã hủy | Phiếu đã hủy |

### Response Schema

```typescript
interface PurchasesResponse {
  success: boolean;
  data: PurchaseOrder[];
  page_number: number;
  page_size: number;
  total_entries: number;
  total_pages: number;
}

interface PurchaseOrder {
  id: string;                     // UUID
  display_id: number;             // Mã hiển thị (số)
  status: -1 | 0 | 1 | 2;
  note: string;

  // Nhà cung cấp
  supplier_products_id: number;   // ID nhà cung cấp
  supplier: {
    id: number;
    name: string;
    custom_id: string;
  };

  // Kho nhập
  warehouse_id: string;
  warehouse: {
    id: string;
    name: string;
  };

  // Sản phẩm trong phiếu
  items: PurchaseItem[];

  // Thời gian
  received_at: number;            // Unix timestamp - ngày về dự kiến
  inserted_at: string;            // ISO datetime - ngày tạo

  // Tùy chọn thanh toán
  auto_create_debts: boolean;     // Tự động tạo công nợ
  not_create_transaction: boolean; // Không tạo phiếu chi

  // Hình ảnh
  images: string[];
}

interface PurchaseItem {
  id: string;
  variation_id: string;
  variation: {
    id: string;
    name: string;
    custom_id: string;
    barcode: string | null;
    product_name: string;
  };
  quantity: number;               // Số lượng nhập
  imported_price: number;         // Giá nhập (VND)
  total_price: number;            // = quantity * imported_price
}
```

### Examples

```bash
# Danh sách tất cả phiếu nhập
bash scripts/suppliers.sh purchases

# Lọc phiếu mới
bash scripts/suppliers.sh purchases "?status=-1"

# Lọc phiếu đã nhập hàng
bash scripts/suppliers.sh purchases "?status=1"

# Phân trang
bash scripts/suppliers.sh purchases "?page=1&page_size=50"
```

## PUT /purchases/{PURCHASE_ID} - Cập nhật phiếu

### Request Body

```typescript
interface UpdatePurchaseRequest {
  purchase: {
    // Bắt buộc
    warehouse_id: string;

    // Tùy chọn
    status?: -1 | 0 | 1 | 2;
    note?: string;
    supplier_products_id?: number;

    // Thời gian
    change_received_at?: boolean;  // Có đổi ngày về không
    received_at?: number;          // Unix timestamp

    // Thanh toán
    auto_create_debts?: boolean;
    not_create_transaction?: boolean;

    // Sản phẩm
    items?: Array<{
      variation_id: string;
      quantity: number;
      imported_price: number;
    }>;

    // Hình ảnh
    images?: string[];
  };
}
```

### Example - Cập nhật trạng thái

```bash
export CONFIRM_WRITE=YES

cat <<'JSON' | bash scripts/suppliers.sh update-purchase "fb056b32-9cf6-4c5a-92de-0eb94db71121"
{
  "purchase": {
    "status": 1,
    "warehouse_id": "c52e67ad-d9d0-4276-abe4-e0c9f1f7d2da"
  }
}
JSON
```

### Example - Cập nhật sản phẩm

```bash
export CONFIRM_WRITE=YES

cat <<'JSON' | bash scripts/suppliers.sh update-purchase "fb056b32-9cf6-4c5a-92de-0eb94db71121"
{
  "purchase": {
    "warehouse_id": "c52e67ad-d9d0-4276-abe4-e0c9f1f7d2da",
    "note": "Nhập đợt 2",
    "supplier_products_id": 169,
    "auto_create_debts": true,
    "items": [
      {
        "variation_id": "29044dcf-2f4c-492f-a0a9-e447b20e21da",
        "quantity": 100,
        "imported_price": 150000
      },
      {
        "variation_id": "abc123-def456",
        "quantity": 50,
        "imported_price": 200000
      }
    ]
  }
}
JSON
```

## POST /purchases/separate - Tách phiếu

Tách một phiếu nhập thành nhiều phiếu nhỏ hơn.

### Request Body

```typescript
interface SeparatePurchaseRequest {
  purchase_id: string;            // ID phiếu gốc
  purchases: Array<{
    warehouse_id: string;
    items: Array<{
      variation_id: string;
      quantity: number;
      imported_price: number;
    }>;
  }>;
}
```

### Example

```bash
export CONFIRM_WRITE=YES

cat <<'JSON' | bash scripts/suppliers.sh split-purchase
{
  "purchase_id": "fb056b32-9cf6-4c5a-92de-0eb94db71121",
  "purchases": [
    {
      "warehouse_id": "warehouse-1-uuid",
      "items": [
        {
          "variation_id": "var-1",
          "quantity": 50,
          "imported_price": 100000
        }
      ]
    },
    {
      "warehouse_id": "warehouse-2-uuid",
      "items": [
        {
          "variation_id": "var-1",
          "quantity": 50,
          "imported_price": 100000
        }
      ]
    }
  ]
}
JSON
```

## cURL Examples

### List purchases

```bash
curl -X GET "https://pos.pages.fm/api/v1/shops/${SHOP_ID}/purchases?status=-2&api_key=${POS_API_KEY}" \
  -H "Content-Type: application/json"
```

### Update purchase

```bash
curl -X PUT "https://pos.pages.fm/api/v1/shops/${SHOP_ID}/purchases/${PURCHASE_ID}?api_key=${POS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "purchase": {
      "status": 1,
      "warehouse_id": "c52e67ad-d9d0-4276-abe4-e0c9f1f7d2da"
    }
  }'
```

## Workflow

Quy trình xử lý phiếu nhập kho điển hình:

```
1. Tạo phiếu (status: -1 Mới)
       ↓
2. Xác nhận với NCC (status: 0 Đã xác nhận)
       ↓
3. Nhận hàng về kho (status: 1 Đã nhập hàng)
       │
       └── Tự động cập nhật tồn kho nếu auto_create_debts = true
       └── Tự động tạo công nợ nếu not_create_transaction = false
```

Hoặc có thể hủy ở bất kỳ bước nào:
```
Bất kỳ trạng thái → status: 2 Đã hủy
```

## Notes

- Khi cập nhật `status = 1` (Đã nhập hàng), hệ thống sẽ tự động cập nhật tồn kho
- `auto_create_debts = true`: Tự động tạo công nợ cho NCC
- `not_create_transaction = true`: Không tạo phiếu chi (thanh toán sau)
- Sử dụng `received_at` với `change_received_at = true` để cập nhật ngày về dự kiến
