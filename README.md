# POScake - POS System Skills Bundle

Bộ Claude Code Skills cho hệ thống Point of Sale (POS).

## Tổng quan Skills

| # | Skill | Mô tả | Loại |
|---|-------|-------|------|
| 1 | **poscake** | Build POS system với Next.js + React + TypeScript | Development |
| 2 | **pos-payments** | Tích hợp thanh toán: Cash, QR, VNPay, Momo, Stripe | Development |
| 3 | **pos-reports** | Analytics dashboards, báo cáo doanh thu, RFM, export | Development |
| 4 | **pos-products** | CRUD sản phẩm, variations, tags, combo | API Integration |
| 5 | **pos-orders** | Quản lý đơn hàng, tracking, tags | API Integration |
| 6 | **pos-customers** | Quản lý khách hàng, điểm thưởng, level | API Integration |
| 7 | **pos-inventory** | Lịch sử tồn kho, báo cáo tồn | API Integration |
| 8 | **pos-warehouses** | Danh mục kho | API Integration |
| 9 | **pos-stocktake** | Kiểm kê hàng hóa | API Integration |
| 10 | **pos-geo** | Tra cứu tỉnh/huyện/xã | API Integration |
| 11 | **pos-webhooks** | Template webhook integration | API Integration |

---

## Quick Start

### 1. Cài đặt Skills

```bash
# Clone repository
git clone https://github.com/nguyenlanh282/poscake.git

# Copy skills vào project
cp -r poscake/skills/* .claude/skills/
cp -r poscake/poscake .claude/skills/

# Hoặc copy vào global
cp -r poscake/skills/* ~/.claude/skills/
```

### 2. Cấu hình Environment

Tạo file `.env` trong project:

```env
# === Pancake POS API ===
POS_API_KEY=your_api_key
SHOP_ID=your_shop_id
POS_BASE_URL=https://pos.pages.fm/api/v1

# === Database ===
DATABASE_URL=postgresql://user:pass@localhost:5432/pos_db

# === Payment Gateways ===
# VNPay
VNPAY_TMN_CODE=
VNPAY_HASH_SECRET=
VNPAY_URL=https://sandbox.vnpayment.vn/paymentv2/vpcpay.html

# Momo
MOMO_PARTNER_CODE=
MOMO_ACCESS_KEY=
MOMO_SECRET_KEY=

# ZaloPay
ZALOPAY_APP_ID=
ZALOPAY_KEY1=
ZALOPAY_KEY2=

# Stripe
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
NEXT_PUBLIC_STRIPE_KEY=

# SePay (VietQR)
SEPAY_API_KEY=
SEPAY_MERCHANT_ID=

# PayOS
PAYOS_CLIENT_ID=
PAYOS_API_KEY=
PAYOS_CHECKSUM_KEY=
```

### 3. Khởi tạo Project mới (Development)

```bash
# Tạo Next.js project
npx create-next-app@latest my-pos --typescript --tailwind --app
cd my-pos

# Cài đặt dependencies
npm install prisma @prisma/client zustand react-hook-form zod
npm install @tanstack/react-query recharts xlsx
npx shadcn@latest init

# Setup Prisma
npx prisma init

# Generate schema (dùng script từ poscake skill)
node .claude/skills/poscake/scripts/generate-schema.js

# Apply database
npx prisma generate
npx prisma db push

# Seed sample data
node .claude/skills/poscake/scripts/seed-data.js
```

### 4. Sử dụng API Skills

```bash
# Set environment
export POS_API_KEY="your_key"
export SHOP_ID="123"

# Đọc dữ liệu
bash scripts/products.sh list "?page=1&page_size=20"
bash scripts/orders.sh get "ORDER_ID"
bash scripts/customers.sh list

# Ghi dữ liệu (cần confirm)
export CONFIRM_WRITE=YES
cat product.json | bash scripts/products.sh create
```

---

## Cấu trúc thư mục

```
poscake/
├── poscake/                      # [SKILL] Build POS với Next.js
│   ├── SKILL.md
│   ├── references/
│   │   ├── products.md           # Product management module
│   │   ├── orders.md             # Order & payment module
│   │   ├── inventory.md          # Inventory management
│   │   ├── reports.md            # Reports & analytics
│   │   └── database.md           # Prisma schema
│   ├── scripts/
│   │   ├── generate-schema.js    # Generate Prisma schema
│   │   └── seed-data.js          # Seed sample data
│   └── assets/
│       └── receipt-template.html # Receipt printing template
│
├── skills/
│   ├── pos-payments/             # [SKILL] Payment integration
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── cash.md           # Cash payment
│   │       ├── qr-bank.md        # VietQR, SePay
│   │       ├── e-wallets.md      # VNPay, Momo, ZaloPay
│   │       └── card.md           # Stripe, PayOS
│   │
│   ├── pos-reports/              # [SKILL] Reports & Analytics
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── revenue.md        # Revenue reports
│   │       ├── products.md       # Product analytics
│   │       ├── customers.md      # Customer analytics, RFM
│   │       ├── inventory.md      # Inventory reports
│   │       └── export.md         # Excel, PDF, CSV export
│   │
│   ├── pos-products/             # [SKILL] Product API
│   ├── pos-orders/               # [SKILL] Order API
│   ├── pos-customers/            # [SKILL] Customer API
│   ├── pos-inventory/            # [SKILL] Inventory API
│   ├── pos-warehouses/           # [SKILL] Warehouse API
│   ├── pos-stocktake/            # [SKILL] Stocktake API
│   ├── pos-geo/                  # [SKILL] Geo API
│   └── pos-webhooks/             # [SKILL] Webhook template
│
├── scripts/                      # Bash scripts cho API calls
│   ├── common.sh
│   ├── products.sh
│   ├── orders.sh
│   ├── customers.sh
│   ├── inventory.sh
│   ├── warehouses.sh
│   ├── stocktake.sh
│   └── geo.sh
│
├── openapi-pos.json              # OpenAPI specification
└── README.md                     # This file
```

---

## Chi tiết từng Skill

### 1. poscake (Development)

Build hệ thống POS hoàn chỉnh với:
- **Products**: CRUD, categories, variants, barcode, bulk import
- **Orders**: Cart, checkout, payments, invoices
- **Inventory**: Stock tracking, import orders, low stock alerts
- **Reports**: Dashboard, revenue, top products, export

**Tech Stack**: Next.js 14, React, TypeScript, Tailwind, Prisma, Zustand, shadcn/ui

### 2. pos-payments (Development)

Tích hợp các phương thức thanh toán:

| Method | Provider | Features |
|--------|----------|----------|
| Cash | - | Tính tiền thừa, mở két tiền |
| QR/Bank | VietQR, SePay | Generate QR, auto-detect payment |
| E-Wallet | VNPay | Redirect, IPN webhook |
| E-Wallet | Momo | QR, callback |
| E-Wallet | ZaloPay | Order API, callback |
| Card | Stripe | Payment Intent, Elements |
| Card | PayOS | Thẻ nội địa Napas |

### 3. pos-reports (Development)

Build analytics dashboards và báo cáo:

| Report Type | Features |
|-------------|----------|
| Revenue | Daily/weekly/monthly, period comparison, payment breakdown |
| Products | Top sellers, category performance, margin analysis, slow movers |
| Customers | New vs returning, RFM segmentation, retention cohorts, LTV |
| Inventory | Stock levels, turnover rate, dead stock, reorder suggestions |
| Export | Excel (xlsx), PDF (jspdf), CSV, scheduled reports |

### 4-11. API Integration Skills

Tích hợp với Pancake POS API (`pos.pages.fm/api/v1`):

| Skill | Endpoints |
|-------|-----------|
| pos-products | `/products`, `/variations`, `/tags_products`, `/combo_products` |
| pos-orders | `/orders`, `/order_source`, `/orders/tags`, `/arrange_shipment` |
| pos-customers | `/customers`, `/point_logs`, `/customer_levels` |
| pos-inventory | `/inventory_histories`, `/inventory_analytics` |
| pos-warehouses | `/warehouses` |
| pos-stocktake | `/stocktakings` |
| pos-geo | `/geo/provinces`, `/geo/districts`, `/geo/communes` |

---

## Safety & Security

### API Skills
- **Read**: Không cần confirm
- **Write**: Yêu cầu `CONFIRM_WRITE=YES`
- **API Key**: Không commit vào repo

### Payment Skills
- Verify webhook signatures
- Use HTTPS only
- Store keys in environment variables
- Test with sandbox/test mode first

---

## License

MIT

## Links

- **Repository**: https://github.com/nguyenlanh282/poscake
- **Pancake POS API**: https://pos.pages.fm/api/v1
