---
name: pos-employees
description: |
  Employee management for Pancake POS. List and manage staff members, departments,
  sale groups, and view employee information. Use when working with staff management,
  employee lists, department organization, or sales team assignments.
version: 1.0.0
allowed-tools: Bash(curl *), Bash(python *), Bash(jq *)
---

# pos-employees

Quản lý nhân viên: danh sách nhân viên, phòng ban, nhóm bán hàng.

## Tính năng

### 1. Danh sách nhân viên (Users)
Reference: [references/employees.md](references/employees.md)
- Xem danh sách nhân viên của shop
- Thông tin cơ bản: tên, email, số điện thoại
- Phòng ban và nhóm bán hàng

### 2. Phòng ban (Departments)
- Tổ chức nhân viên theo phòng ban
- Quản lý cấu trúc tổ chức

### 3. Nhóm bán hàng (Sale Groups)
- Phân chia nhân viên theo ca/nhóm
- Hỗ trợ tính KPI và báo cáo

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

Script: `scripts/employees.sh`

### Danh sách nhân viên

```bash
# Lấy tất cả nhân viên
bash scripts/employees.sh list
```

## Guardrails

- Không ghi dữ liệu khi chưa set `CONFIRM_WRITE=YES`
- Với thao tác ghi: luôn chạy 1 lệnh GET trước để xác nhận ID/shape dữ liệu
- Không lưu API key vào repo

## Data Models

### Employee (Nhân viên)

```typescript
interface Employee {
  shop_id: number;
  user_id: string;                // UUID

  user: {
    id: string;                   // UUID
    name: string;                 // Tên nhân viên
    email: string;                // Email
    phone_number: string | null;  // Số điện thoại
    fb_id: string | null;         // Facebook ID (nếu đăng nhập qua FB)
  };

  department: {
    id: number;
    name: string;                 // VD: "Sales", "Marketing", "Support"
  } | null;

  sale_group: {
    id: number;
    name: string;                 // VD: "Ca sáng", "Ca chiều", "Nhóm A"
  } | null;
}
```

### Department (Phòng ban)

```typescript
interface Department {
  id: number;
  name: string;                   // Tên phòng ban
}
```

### Sale Group (Nhóm bán hàng)

```typescript
interface SaleGroup {
  id: number;
  name: string;                   // Tên nhóm bán hàng
}
```

## Endpoint thuộc skill này

| Endpoint | Method | Mô tả |
|----------|--------|-------|
| `/shops/{SHOP_ID}/users` | GET | Danh sách nhân viên |

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
        "email": "minhtuan@example.com",
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

## Use Cases

### 1. Xem danh sách nhân viên để gán vào đơn hàng

```bash
# Lấy danh sách nhân viên
bash scripts/employees.sh list

# Sử dụng user_id để gán nhân viên phụ trách đơn
```

### 2. Lọc nhân viên theo phòng ban

```bash
# Lấy danh sách và lọc bằng jq
bash scripts/employees.sh list | jq '.data[] | select(.department.name == "Sales")'
```

### 3. Tìm nhân viên theo tên

```bash
bash scripts/employees.sh list | jq '.data[] | select(.user.name | contains("Hoang"))'
```

### 4. Lấy danh sách email nhân viên

```bash
bash scripts/employees.sh list | jq -r '.data[].user.email'
```

## Tham chiếu

- OpenAPI spec: `openapi-pos.json` (ở root bundle)
- Related skills: `pos-orders`, `pos-customers`, `pos-reports`
