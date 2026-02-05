# Employees (Nhân viên)

API endpoint để lấy danh sách nhân viên của shop.

## Endpoint

```
GET /shops/{SHOP_ID}/users
```

## Response Schema

```typescript
interface EmployeesResponse {
  success: boolean;
  data: Employee[];
}

interface Employee {
  shop_id: number;                // ID của shop
  user_id: string;                // UUID của nhân viên

  user: {
    id: string;                   // UUID (giống user_id)
    name: string;                 // Tên nhân viên
    email: string;                // Email
    phone_number: string | null;  // Số điện thoại (có thể null)
    fb_id: string | null;         // Facebook ID (nếu đăng nhập qua FB)
  };

  department: {
    id: number;                   // ID phòng ban
    name: string;                 // Tên phòng ban
  } | null;

  sale_group: {
    id: number;                   // ID nhóm bán hàng
    name: string;                 // Tên nhóm bán hàng
  } | null;
}
```

## Example

```bash
export POS_API_KEY="your-api-key"
export SHOP_ID="123"

bash scripts/employees.sh list
```

## cURL Example

```bash
curl -X GET "https://pos.pages.fm/api/v1/shops/${SHOP_ID}/users?api_key=${POS_API_KEY}" \
  -H "Content-Type: application/json"
```

## Response Example

```json
{
  "success": true,
  "data": [
    {
      "shop_id": 7,
      "user_id": "8fbe2a6f-b0b2-4227-a698-19d18c43f7c8",
      "user": {
        "id": "8fbe2a6f-b0b2-4227-a698-19d18c43f7c8",
        "name": "Hoang Anh",
        "email": "hoanganh@example.com",
        "phone_number": "0901234567",
        "fb_id": null
      },
      "department": {
        "id": 933,
        "name": "Sales"
      },
      "sale_group": {
        "id": 30,
        "name": "Ca sáng"
      }
    },
    {
      "shop_id": 7,
      "user_id": "abc123-def456",
      "user": {
        "id": "abc123-def456",
        "name": "Minh Tuan",
        "email": "2042723249341651@facebook.com",
        "phone_number": null,
        "fb_id": "2042723249341651"
      },
      "department": {
        "id": 934,
        "name": "Support"
      },
      "sale_group": null
    }
  ]
}
```

## Common Use Cases

### 1. Lấy danh sách tất cả nhân viên

```bash
bash scripts/employees.sh list
```

### 2. Lọc nhân viên theo phòng ban

```bash
# Chỉ lấy nhân viên Sales
bash scripts/employees.sh list | jq '.data[] | select(.department.name == "Sales")'

# Lấy tên nhân viên Sales
bash scripts/employees.sh list | jq -r '.data[] | select(.department.name == "Sales") | .user.name'
```

### 3. Lọc nhân viên theo nhóm bán hàng

```bash
# Nhân viên ca sáng
bash scripts/employees.sh list | jq '.data[] | select(.sale_group.name == "Ca sáng")'
```

### 4. Tìm nhân viên theo tên

```bash
# Tìm nhân viên có tên chứa "Hoang"
bash scripts/employees.sh list | jq '.data[] | select(.user.name | contains("Hoang"))'
```

### 5. Lấy thông tin liên hệ

```bash
# Lấy tất cả email
bash scripts/employees.sh list | jq -r '.data[].user.email'

# Lấy số điện thoại (bỏ qua null)
bash scripts/employees.sh list | jq -r '.data[].user.phone_number | select(. != null)'
```

### 6. Đếm nhân viên theo phòng ban

```bash
bash scripts/employees.sh list | jq '[.data[] | .department.name] | group_by(.) | map({department: .[0], count: length})'
```

### 7. Tạo bảng tóm tắt

```bash
bash scripts/employees.sh list | jq -r '.data[] | [.user.name, .user.email, (.department.name // "N/A"), (.sale_group.name // "N/A")] | @tsv'
```

## Integration Examples

### Gán nhân viên phụ trách đơn hàng

Khi tạo/cập nhật đơn hàng, sử dụng `user_id` để gán nhân viên:

```bash
# 1. Lấy danh sách nhân viên
employees=$(bash scripts/employees.sh list)

# 2. Lấy user_id của nhân viên cần gán
user_id=$(echo "$employees" | jq -r '.data[] | select(.user.name == "Hoang Anh") | .user_id')

# 3. Sử dụng user_id trong đơn hàng
echo "Assigned to: $user_id"
```

### Báo cáo nhân viên theo phòng ban

```bash
bash scripts/employees.sh list | jq '
  .data
  | group_by(.department.name)
  | map({
      department: .[0].department.name,
      employees: [.[].user.name],
      count: length
    })
'
```

## Notes

- Endpoint này chỉ trả về nhân viên đã được thêm vào shop
- `fb_id` có giá trị khi nhân viên đăng nhập bằng Facebook
- `department` và `sale_group` có thể là `null` nếu chưa được gán
- Email có dạng `xxxxx@facebook.com` khi đăng nhập qua Facebook

## Related Endpoints

Các endpoint liên quan thường được sử dụng cùng với employees:

- `/shops/{SHOP_ID}/orders` - Đơn hàng (có thể lọc theo nhân viên)
- `/shops/{SHOP_ID}/customers` - Khách hàng (có thể gán nhân viên phụ trách)
