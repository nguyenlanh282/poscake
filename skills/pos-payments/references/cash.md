# Cash Payment

## Flow

```
1. Cashier nhập số tiền khách đưa
2. Hệ thống tính tiền thừa
3. Mở két tiền (nếu có)
4. In hóa đơn
5. Cập nhật trạng thái đơn hàng
```

## Component

```tsx
interface CashPaymentProps {
  total: number;
  onComplete: (payment: Payment) => void;
}

function CashPayment({ total, onComplete }: CashPaymentProps) {
  const [received, setReceived] = useState<number>(0);
  const change = received - total;

  const quickAmounts = [
    total,                              // Exact
    Math.ceil(total / 10000) * 10000,   // Round up to 10k
    Math.ceil(total / 50000) * 50000,   // Round up to 50k
    Math.ceil(total / 100000) * 100000, // Round up to 100k
  ];

  const handleConfirm = () => {
    if (received >= total) {
      onComplete({
        method: 'cash',
        amount: total,
        status: 'completed',
        metadata: { received, change }
      });
    }
  };

  return (
    <div>
      <div>Total: {formatCurrency(total)}</div>
      <div className="quick-amounts">
        {quickAmounts.map(amt => (
          <Button key={amt} onClick={() => setReceived(amt)}>
            {formatCurrency(amt)}
          </Button>
        ))}
      </div>
      <Input
        type="number"
        value={received}
        onChange={e => setReceived(Number(e.target.value))}
      />
      {received >= total && (
        <div className="change">
          Change: {formatCurrency(change)}
        </div>
      )}
      <Button onClick={handleConfirm} disabled={received < total}>
        Confirm Payment
      </Button>
    </div>
  );
}
```

## Cash Drawer Integration

```typescript
// USB cash drawer (ESC/POS command)
async function openCashDrawer() {
  const drawer = await navigator.serial.requestPort();
  await drawer.open({ baudRate: 9600 });

  const writer = drawer.writable.getWriter();
  // ESC/POS command to open drawer
  await writer.write(new Uint8Array([0x1B, 0x70, 0x00, 0x19, 0xFA]));
  writer.releaseLock();
}

// Network printer with drawer
async function openDrawerViaPrinter(printerIP: string) {
  const cmd = Buffer.from([0x1B, 0x70, 0x00, 0x19, 0xFA]);
  await fetch(`http://${printerIP}:9100`, {
    method: 'POST',
    body: cmd
  });
}
```

## Denomination Counter

```typescript
interface Denomination {
  value: number;
  count: number;
}

const vnDenominations = [
  500000, 200000, 100000, 50000, 20000, 10000, 5000, 2000, 1000, 500
];

function calculateDenominations(amount: number): Denomination[] {
  const result: Denomination[] = [];
  let remaining = amount;

  for (const value of vnDenominations) {
    const count = Math.floor(remaining / value);
    if (count > 0) {
      result.push({ value, count });
      remaining -= value * count;
    }
  }
  return result;
}
```

## End of Day Cash Report

```typescript
interface CashReport {
  openingBalance: number;
  cashSales: number;
  cashRefunds: number;
  expectedBalance: number;
  actualBalance: number;
  difference: number;
}
```
