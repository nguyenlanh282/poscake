# E-Wallets Integration

## VNPay

### Setup

```bash
npm install vnpay
```

### Create Payment URL

```typescript
import { VNPay, ignoreLogger } from 'vnpay';

const vnpay = new VNPay({
  tmnCode: process.env.VNPAY_TMN_CODE!,
  secureSecret: process.env.VNPAY_HASH_SECRET!,
  vnpayHost: 'https://sandbox.vnpayment.vn',
  testMode: true,
  hashAlgorithm: 'SHA512',
  enableLog: true,
  loggerFn: ignoreLogger
});

async function createVNPayURL(orderId: string, amount: number, ipAddr: string) {
  const paymentUrl = vnpay.buildPaymentUrl({
    vnp_Amount: amount,
    vnp_IpAddr: ipAddr,
    vnp_TxnRef: orderId,
    vnp_OrderInfo: `Payment for order ${orderId}`,
    vnp_OrderType: 'other',
    vnp_ReturnUrl: `${process.env.APP_URL}/payment/vnpay/return`,
    vnp_Locale: 'vn'
  });

  return paymentUrl;
}
```

### Verify Return URL

```typescript
// GET /payment/vnpay/return
export async function GET(req: Request) {
  const url = new URL(req.url);
  const params = Object.fromEntries(url.searchParams);

  const isValid = vnpay.verifyReturnUrl(params);
  if (!isValid) {
    return redirect('/payment/failed?reason=invalid_signature');
  }

  const { vnp_ResponseCode, vnp_TxnRef, vnp_Amount } = params;

  if (vnp_ResponseCode === '00') {
    await updateOrderPayment(vnp_TxnRef, {
      status: 'paid',
      amount: Number(vnp_Amount) / 100
    });
    return redirect(`/orders/${vnp_TxnRef}/success`);
  }

  return redirect('/payment/failed');
}
```

### IPN Webhook

```typescript
// POST /api/webhooks/vnpay
export async function POST(req: Request) {
  const body = await req.json();

  const isValid = vnpay.verifyIpnCall(body);
  if (!isValid) {
    return Response.json({ RspCode: '97', Message: 'Invalid signature' });
  }

  const { vnp_TxnRef, vnp_ResponseCode } = body;

  // Check order exists
  const order = await getOrder(vnp_TxnRef);
  if (!order) {
    return Response.json({ RspCode: '01', Message: 'Order not found' });
  }

  // Already processed
  if (order.paymentStatus === 'paid') {
    return Response.json({ RspCode: '02', Message: 'Already processed' });
  }

  if (vnp_ResponseCode === '00') {
    await updateOrderPayment(vnp_TxnRef, { status: 'paid' });
  }

  return Response.json({ RspCode: '00', Message: 'Success' });
}
```

---

## Momo

### Create Payment

```typescript
import crypto from 'crypto';

const MOMO_CONFIG = {
  partnerCode: process.env.MOMO_PARTNER_CODE!,
  accessKey: process.env.MOMO_ACCESS_KEY!,
  secretKey: process.env.MOMO_SECRET_KEY!,
  endpoint: 'https://test-payment.momo.vn/v2/gateway/api/create'
};

async function createMomoPayment(orderId: string, amount: number) {
  const requestId = `${orderId}_${Date.now()}`;
  const orderInfo = `Payment for order ${orderId}`;
  const redirectUrl = `${process.env.APP_URL}/payment/momo/return`;
  const ipnUrl = `${process.env.APP_URL}/api/webhooks/momo`;
  const requestType = 'payWithMethod';
  const extraData = '';

  const rawSignature = [
    `accessKey=${MOMO_CONFIG.accessKey}`,
    `amount=${amount}`,
    `extraData=${extraData}`,
    `ipnUrl=${ipnUrl}`,
    `orderId=${orderId}`,
    `orderInfo=${orderInfo}`,
    `partnerCode=${MOMO_CONFIG.partnerCode}`,
    `redirectUrl=${redirectUrl}`,
    `requestId=${requestId}`,
    `requestType=${requestType}`
  ].join('&');

  const signature = crypto
    .createHmac('sha256', MOMO_CONFIG.secretKey)
    .update(rawSignature)
    .digest('hex');

  const response = await fetch(MOMO_CONFIG.endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      partnerCode: MOMO_CONFIG.partnerCode,
      accessKey: MOMO_CONFIG.accessKey,
      requestId,
      amount,
      orderId,
      orderInfo,
      redirectUrl,
      ipnUrl,
      extraData,
      requestType,
      signature,
      lang: 'vi'
    })
  });

  const data = await response.json();
  return data.payUrl;
}
```

---

## ZaloPay

### Create Order

```typescript
import crypto from 'crypto';

const ZALOPAY_CONFIG = {
  appId: process.env.ZALOPAY_APP_ID!,
  key1: process.env.ZALOPAY_KEY1!,
  key2: process.env.ZALOPAY_KEY2!,
  endpoint: 'https://sb-openapi.zalopay.vn/v2/create'
};

async function createZaloPayOrder(orderId: string, amount: number) {
  const appTransId = `${formatDate(new Date(), 'yyMMdd')}_${orderId}`;

  const order = {
    app_id: ZALOPAY_CONFIG.appId,
    app_trans_id: appTransId,
    app_user: 'user',
    app_time: Date.now(),
    amount,
    item: JSON.stringify([]),
    description: `Payment for order ${orderId}`,
    embed_data: JSON.stringify({ redirecturl: `${process.env.APP_URL}/payment/zalopay/return` }),
    callback_url: `${process.env.APP_URL}/api/webhooks/zalopay`
  };

  const data = `${order.app_id}|${order.app_trans_id}|${order.app_user}|${order.amount}|${order.app_time}|${order.embed_data}|${order.item}`;
  const mac = crypto.createHmac('sha256', ZALOPAY_CONFIG.key1).update(data).digest('hex');

  const response = await fetch(ZALOPAY_CONFIG.endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ ...order, mac } as any)
  });

  const result = await response.json();
  return result.order_url;
}
```
