---
name: pos-suppliers
description: |
  Supplier and purchase order management for Pancake POS. Manage supplier information,
  create and track purchase orders (import inventory from suppliers), handle supplier
  debt, and split purchase orders. Use when working with supplier management, purchase
  orders, inventory imports, or supplier debt tracking.
version: 1.0.0
allowed-tools: Bash(curl *), Bash(python *), Bash(jq *)
---

# pos-suppliers

Quản lý nhà cung cấp và phiếu nhập kho: danh sách NCC, phiếu nhập, công nợ, tách phiếu.

## Tính năng

### 1. Quản lý nhà cung cấp (Suppliers)
Reference: [references/suppliers.md](references/suppliers.md)
- Danh sách nhà cung cấp
- Thông tin liên hệ, địa chỉ, thanh toán
- Theo dõi công nợ và tổng mua

### 2. Phiếu nhập kho (Purchase Orders)
Reference: [references/purchases.md](references/purchases.md)
- Danh sách phiếu nhập kho
- Tạo, cập nhật, hủy phiếu nhập
- Theo dõi trạng thái: Mới → Xác nhận → Nhập hàng

### 3. Tách phiếu nhập (Split Purchase)
- Tách một phiếu nhập thành nhiều phiếu

## Thiết lập môi trường (bắt buộc)

```bash
export POS_API_KEY="your-api-key"   # API key (query param: api_key)
export SHOP_ID="123"                 # Shop ID
```

Tuỳ chọn:
```bash
export POS_BASE_URL="https://pos.pages.fm/api/v1"  # Mặc định
```

## Cách gọi nhanh

Script: `scripts/suppliers.sh`

### Nhà cung cấp

```bash
# Danh sách nhà cung cấp
bash scripts/suppliers.sh list

# Phân trang
bash scripts/suppliers.sh list "?page=1&page_size=50"
```

### Phiếu nhập kho

```bash
# Danh sách phiếu nhập
bash scripts/suppliers.sh purchases

# Lọc theo trạng thái
bash scripts/suppliers.sh purchases "?status=1"  # Đã nhập hàng

# Cập nhật phiếu nhập (cần CONFIRM_WRITE=YES)
export CONFIRM_WRITE=YES
cat payload.json | bash scripts/suppliers.sh update-purchase "PURCHASE_ID"
```

### Tách phiếu

```bash
export CONFIRM_WRITE=YES
cat split-payload.json | bash scripts/suppliers.sh split-purchase
```

## Guardrails

- Không ghi dữ liệu khi chưa set `CONFIRM_WRITE=YES`
- Với thao tác ghi: luôn chạy 1 lệnh GET trước để xác nhận ID/shape dữ liệu
- Không lưu API key vào repo

## Data Models

### Supplier (Nhà cung cấp)

```typescript
interface Supplier {
  id: number;
  custom_id: string;              // Mã NCC tùy chỉnh
  name: string;
  phone_number: string;

  // Địa chỉ
  address: string;
  full_address: string;
  province_id: string;
  district_id: string;
  commune_id: string;
  country_code: number;

  // Thông tin thanh toán
  payment_info: {
    account_name: string;
    account_number: string;
    partner_code: string;         // Mã ngân hàng
  };

  // Thống kê
  debt_must_pay: string;          // Công nợ phải trả (VND)
  total_purchase: string;         // Tổng mua (VND)

  // Khác
  description: string | null;
  images: string[];
  tags: number[];
  type: number;
  is_activated: boolean;
}
```

### Purchase Order (Phiếu nhập kho)

```typescript
interface PurchaseOrder {
  id: string;                     // UUID
  display_id: number;             // Mã hiển thị
  status: PurchaseStatus;
  note: string;

  // Nhà cung cấp
  supplier_products_id: number;
  supplier: Supplier;

  // Kho
  warehouse_id: string;

  // Sản phẩm
  items: Array<{
    variation_id: string;
    quantity: number;
    imported_price: number;       // Giá nhập
  }>;

  // Thời gian
  received_at: number;            // Unix timestamp - ngày về dự kiến
  inserted_at: string;            // ISO datetime

  // Thanh toán
  auto_create_debts: boolean;     // Tạo công nợ tự động
  not_create_transaction: boolean; // Không tạo phiếu chi

  images: string[];
}

type PurchaseStatus = -1 | 0 | 1 | 2;
// -1: Mới
//  0: Đã xác nhận
//  1: Đã nhập hàng
//  2: Đã hủy
```

## Endpoint thuộc skill này

| Endpoint | Method | Mô tả |
|----------|--------|-------|
| `/shops/{SHOP_ID}/supplier` | GET | Danh sách nhà cung cấp |
| `/shops/{SHOP_ID}/purchases` | GET | Danh sách phiếu nhập kho |
| `/shops/{SHOP_ID}/purchases/{PURCHASE_ID}` | PUT | Cập nhật phiếu nhập kho |
| `/shops/{SHOP_ID}/purchases/separate` | POST | Tách phiếu nhập kho |

## Query Parameters

### supplier (GET)

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| page | integer | No | Số trang (default: 1) |
| page_size | integer | No | Kích thước trang (default: 30) |

### purchases (GET)

| Param | Type | Required | Mô tả |
|-------|------|----------|-------|
| page | integer | No | Số trang (default: 1) |
| page_size | integer | No | Kích thước trang (default: 30) |
| status | integer | No | Trạng thái: -2 (tất cả), -1 (mới), 0 (xác nhận), 1 (nhập hàng), 2 (hủy) |
| type | string | No | Loại (default: "product") |
| get_time_import | boolean | No | Lấy thời gian nhập hàng |

## Status Codes

| Status | Tên | Mô tả |
|--------|-----|-------|
| -1 | Mới | Phiếu vừa tạo, chưa xử lý |
| 0 | Đã xác nhận | Đã xác nhận với NCC |
| 1 | Đã nhập hàng | Hàng đã về kho |
| 2 | Đã hủy | Phiếu đã hủy |

## Tham chiếu

- OpenAPI spec: `openapi-pos.json` (ở root bundle)
- Related skills: `pos-inventory`, `pos-warehouses`, `pos-products`
