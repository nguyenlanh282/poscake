# Suppliers (Nhà cung cấp)

API endpoint để quản lý danh sách nhà cung cấp.

## Endpoint

```
GET /shops/{SHOP_ID}/supplier
```

## Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `page` | integer | No | 1 | Số trang hiện tại |
| `page_size` | integer | No | 30 | Số record mỗi trang |

## Response Schema

```typescript
interface SuppliersResponse {
  success: boolean;
  data: Supplier[];
  page_number: number;
  page_size: number;
  total_entries: number;
  total_pages: number;
  total_debt: number;           // Tổng công nợ của tất cả NCC
}

interface Supplier {
  id: number;
  custom_id: string;            // Mã NCC tùy chỉnh (VD: "NCC001")
  name: string;                 // Tên nhà cung cấp
  phone_number: string;
  description: string | null;

  // Địa chỉ
  address: string;              // Địa chỉ chi tiết
  full_address: string;         // Địa chỉ đầy đủ
  province_id: string;          // Mã tỉnh/thành
  district_id: string;          // Mã quận/huyện
  commune_id: string;           // Mã phường/xã
  country_code: number;         // Mã quốc gia (84 = Vietnam)

  // Thông tin thanh toán
  payment_info: {
    account_name: string;       // Tên tài khoản
    account_number: string;     // Số tài khoản
    partner_code: string;       // Mã ngân hàng (VD: "CTG", "VCB", "TCB")
  };

  // Thống kê
  debt_must_pay: string;        // Công nợ phải trả (VND)
  total_purchase: string;       // Tổng giá trị đã mua (VND)

  // Khác
  images: string[];             // Danh sách URL hình ảnh
  tags: number[];               // Danh sách tag IDs
  type: number;                 // Loại NCC
  is_activated: boolean;        // Trạng thái kích hoạt
}
```

## Examples

### Lấy danh sách nhà cung cấp

```bash
export POS_API_KEY="your-api-key"
export SHOP_ID="123"

bash scripts/suppliers.sh list
```

### Phân trang

```bash
bash scripts/suppliers.sh list "?page=2&page_size=50"
```

## cURL Example

```bash
curl -X GET "https://pos.pages.fm/api/v1/shops/${SHOP_ID}/supplier?api_key=${POS_API_KEY}" \
  -H "Content-Type: application/json"
```

## Response Example

```json
{
  "success": true,
  "data": [
    {
      "id": 988,
      "custom_id": "HH",
      "name": "CT TNHH Hồng Hà",
      "phone_number": "0983239908",
      "description": null,
      "address": "90 cầu giấy",
      "full_address": "90 cầu giấy, Phường Dịch Vọng, Quận Cầu Giấy, Hà Nội",
      "province_id": "101",
      "district_id": "10113",
      "commune_id": "1011309",
      "country_code": 84,
      "payment_info": {
        "account_name": "THANG LONG",
        "account_number": "123456789",
        "partner_code": "CTG"
      },
      "debt_must_pay": "88334",
      "total_purchase": "344444",
      "images": [
        "https://content.pancake.vn/user-content/image.png"
      ],
      "tags": [5],
      "type": 0,
      "is_activated": true
    }
  ],
  "page_number": 1,
  "page_size": 30,
  "total_entries": 15,
  "total_pages": 1,
  "total_debt": 500000
}
```

## Bank Partner Codes

Một số mã ngân hàng phổ biến:

| Code | Ngân hàng |
|------|-----------|
| `VCB` | Vietcombank |
| `CTG` | Vietinbank |
| `TCB` | Techcombank |
| `ACB` | ACB |
| `MBB` | MB Bank |
| `VPB` | VPBank |
| `TPB` | TPBank |
| `STB` | Sacombank |
| `BID` | BIDV |
| `AGR` | Agribank |

## Notes

- `debt_must_pay` và `total_purchase` được trả về dạng string (VND)
- `total_debt` trong response là tổng công nợ của tất cả NCC
- Địa chỉ được tách thành các cấp: tỉnh/thành → quận/huyện → phường/xã
- Sử dụng skill `pos-geo` để lấy danh sách tỉnh/quận/phường
