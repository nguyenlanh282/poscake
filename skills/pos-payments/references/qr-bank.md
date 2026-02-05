# QR Code & Bank Transfer

## VietQR Standard

VietQR là tiêu chuẩn QR thanh toán liên ngân hàng tại Việt Nam.

### Generate VietQR

```typescript
import QRCode from 'qrcode';

interface VietQRParams {
  bankBin: string;      // Bank BIN (970415 = Vietinbank)
  accountNo: string;
  amount?: number;
  description?: string;
  accountName?: string;
}

function generateVietQRContent(params: VietQRParams): string {
  const { bankBin, accountNo, amount, description } = params;

  // EMVCo QR format
  let content = '';
  content += '000201';                           // Payload Format Indicator
  content += '010212';                           // Static QR
  content += `38${(15 + accountNo.length).toString().padStart(2, '0')}`;
  content += '0010A000000727';                   // NAPAS identifier
  content += `01${bankBin.length.toString().padStart(2, '0')}${bankBin}`;
  content += `02${accountNo.length.toString().padStart(2, '0')}${accountNo}`;
  content += '5303704';                          // Currency (VND)

  if (amount) {
    const amtStr = amount.toString();
    content += `54${amtStr.length.toString().padStart(2, '0')}${amtStr}`;
  }
  content += '5802VN';                           // Country

  if (description) {
    content += `62${(4 + description.length).toString().padStart(2, '0')}`;
    content += `08${description.length.toString().padStart(2, '0')}${description}`;
  }

  // Calculate CRC
  content += '6304';
  const crc = calculateCRC16(content);
  content += crc;

  return content;
}

async function generateQRImage(content: string): Promise<string> {
  return QRCode.toDataURL(content, { width: 300, margin: 2 });
}
```

### Bank BIN Codes

| Bank | BIN |
|------|-----|
| Vietcombank | 970436 |
| Vietinbank | 970415 |
| BIDV | 970418 |
| Techcombank | 970407 |
| MB Bank | 970422 |
| ACB | 970416 |
| VPBank | 970432 |
| TPBank | 970423 |

## SePay Integration

SePay cung cấp API để generate VietQR và verify thanh toán.

### Setup

```bash
npm install sepay-sdk
```

### Generate QR

```typescript
import { SePay } from 'sepay-sdk';

const sepay = new SePay({
  apiKey: process.env.SEPAY_API_KEY,
  merchantId: process.env.SEPAY_MERCHANT_ID
});

async function createPaymentQR(orderId: string, amount: number) {
  const result = await sepay.createQR({
    orderId,
    amount,
    description: `Payment for order ${orderId}`,
    expireIn: 15 * 60  // 15 minutes
  });

  return {
    qrCode: result.qrDataUrl,
    transactionId: result.transactionId
  };
}
```

### Webhook Verification

```typescript
// POST /api/webhooks/sepay
export async function POST(req: Request) {
  const body = await req.json();
  const signature = req.headers.get('x-sepay-signature');

  // Verify signature
  const isValid = sepay.verifyWebhook(body, signature);
  if (!isValid) {
    return Response.json({ error: 'Invalid signature' }, { status: 401 });
  }

  const { orderId, transactionId, amount, status } = body;

  if (status === 'success') {
    await updateOrderPayment(orderId, {
      status: 'paid',
      transactionId,
      paidAmount: amount
    });
  }

  return Response.json({ received: true });
}
```

## Component

```tsx
function QRPayment({ orderId, amount, onComplete }: QRPaymentProps) {
  const [qrCode, setQrCode] = useState<string>();
  const [status, setStatus] = useState<'pending' | 'checking' | 'success'>('pending');

  useEffect(() => {
    createPaymentQR(orderId, amount).then(({ qrCode }) => setQrCode(qrCode));
  }, [orderId, amount]);

  // Poll for payment status
  useEffect(() => {
    const interval = setInterval(async () => {
      const payment = await checkPaymentStatus(orderId);
      if (payment.status === 'completed') {
        setStatus('success');
        onComplete(payment);
        clearInterval(interval);
      }
    }, 3000);

    return () => clearInterval(interval);
  }, [orderId]);

  return (
    <div className="text-center">
      <p>Scan QR to pay {formatCurrency(amount)}</p>
      {qrCode && <img src={qrCode} alt="VietQR" className="mx-auto" />}
      <p className="text-sm text-muted">Auto-detecting payment...</p>
    </div>
  );
}
```
