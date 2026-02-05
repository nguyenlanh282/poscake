---
name: pos-payments
description: |
  Integrate payment methods for POS systems: cash payments (change calculation, cash drawer),
  QR/bank transfers (VietQR, bank API), e-wallets (VNPay, Momo, ZaloPay), card payments
  (Stripe, PayOS). Use when implementing checkout flows, payment processing, refunds,
  payment reconciliation, or building payment integration for Vietnamese market.
version: 1.0.0
---

# POS Payments Integration

Tích hợp các phương thức thanh toán cho hệ thống POS.

## Phương thức thanh toán

### 1. Cash Payment
Reference: [references/payments/cash.md](references/payments/cash.md)
- Tính tiền thừa, mở két tiền, in hóa đơn

### 2. QR / Bank Transfer
Reference: [references/payments/qr-bank.md](references/payments/qr-bank.md)
- VietQR generation, bank transfer verification, SePay integration

### 3. E-Wallets
Reference: [references/payments/e-wallets.md](references/payments/e-wallets.md)
- VNPay, Momo, ZaloPay integration

### 4. Card Payment
Reference: [references/payments/card.md](references/payments/card.md)
- Stripe, PayOS cho thẻ nội địa/quốc tế

## Data Model

```typescript
interface Payment {
  id: string;
  orderId: string;
  method: PaymentMethod;
  amount: number;
  status: PaymentStatus;
  transactionId?: string;    // From gateway
  metadata?: Record<string, any>;
  createdAt: Date;
  completedAt?: Date;
}

type PaymentMethod = 'cash' | 'bank_transfer' | 'vnpay' | 'momo' | 'zalopay' | 'card';
type PaymentStatus = 'pending' | 'processing' | 'completed' | 'failed' | 'refunded';
```

## Components

```
components/pos/payments/
├── PaymentSelector.tsx      # Chọn phương thức thanh toán
├── CashPayment.tsx          # Nhập tiền khách đưa, tính thừa
├── QRPayment.tsx            # Hiển thị QR code
├── EWalletPayment.tsx       # Redirect/QR e-wallet
├── CardPayment.tsx          # Form nhập thẻ
├── PaymentStatus.tsx        # Trạng thái thanh toán
└── RefundModal.tsx          # Hoàn tiền
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/payments/create` | Tạo payment intent |
| POST | `/api/payments/verify` | Xác nhận thanh toán |
| POST | `/api/payments/refund` | Hoàn tiền |
| POST | `/api/webhooks/vnpay` | VNPay callback |
| POST | `/api/webhooks/momo` | Momo callback |
| GET | `/api/payments/:id` | Chi tiết payment |

## Environment Variables

```env
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

# SePay (VietQR)
SEPAY_API_KEY=
SEPAY_MERCHANT_ID=
```

## Webhook Security

- Verify signature từ payment gateway
- Idempotency check (transaction ID)
- Log tất cả webhook requests
- Retry mechanism cho failed webhooks
