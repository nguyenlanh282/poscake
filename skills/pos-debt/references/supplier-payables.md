# Supplier Payables (Accounts Payable)

Quản lý công nợ với nhà cung cấp - theo dõi các khoản phải trả.

## Overview

Supplier payables theo dõi các hóa đơn mua hàng và lịch thanh toán cho nhà cung cấp.

## Data Model

```typescript
interface SupplierPayable {
  supplierId: string;
  supplierName: string;

  // Balances
  totalPayable: number;       // Total owed
  overdueAmount: number;

  // Terms
  paymentTermDays: number;
  earlyPaymentDiscount?: {
    days: number;             // Pay within X days
    discountPercent: number;  // Get Y% off
  };

  // Stats
  avgPaymentDays: number;
  onTimePaymentRate: number;

  // Bills
  pendingBills: number;
  overdueBills: number;
}

interface PurchaseBill {
  id: string;
  billNumber: string;         // BILL-2024-0001
  supplierId: string;
  purchaseOrderId?: string;
  goodsReceiptId?: string;

  // Amounts
  subtotal: number;
  tax: number;
  total: number;
  paidAmount: number;
  balance: number;

  // Dates
  billDate: Date;
  dueDate: Date;
  paidDate?: Date;

  // Status
  status: BillStatus;

  // Payments
  payments: BillPayment[];

  // Reference
  supplierInvoiceNumber?: string;
  attachments?: string[];
  notes?: string;
}

type BillStatus = 'pending' | 'approved' | 'partial' | 'paid' | 'overdue' | 'disputed';

interface BillPayment {
  id: string;
  billId: string;
  amount: number;
  method: PaymentMethod;
  bankAccount?: string;
  referenceNumber?: string;
  paymentDate: Date;
  paidBy: string;
  notes?: string;
}

interface PaymentSchedule {
  id: string;
  supplierId: string;
  bills: ScheduledBill[];
  scheduledDate: Date;
  totalAmount: number;
  status: 'scheduled' | 'completed' | 'cancelled';
}

interface ScheduledBill {
  billId: string;
  billNumber: string;
  amount: number;
  isPartial: boolean;
}
```

## Database Schema

```prisma
model SupplierPayable {
  id              String   @id @default(cuid())
  supplierId      String   @unique
  supplier        Supplier @relation(fields: [supplierId], references: [id])

  totalPayable    Decimal  @default(0)
  overdueAmount   Decimal  @default(0)

  paymentTermDays Int      @default(30)
  earlyPaymentDays Int?
  earlyPaymentDiscount Decimal?

  avgPaymentDays     Float  @default(0)
  onTimePaymentRate  Float  @default(100)

  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  bills           PurchaseBill[]
}

model PurchaseBill {
  id              String   @id @default(cuid())
  billNumber      String   @unique
  supplierId      String
  payableId       String
  purchaseOrderId String?
  goodsReceiptId  String?

  subtotal        Decimal
  tax             Decimal  @default(0)
  total           Decimal
  paidAmount      Decimal  @default(0)
  balance         Decimal

  billDate        DateTime
  dueDate         DateTime
  paidDate        DateTime?

  status          BillStatus @default(PENDING)

  supplierInvoiceNumber String?
  notes           String?

  payable         SupplierPayable @relation(fields: [payableId], references: [id])
  payments        BillPayment[]

  @@index([supplierId])
  @@index([status])
  @@index([dueDate])
}
```

## Service Implementation

```typescript
// services/supplierPayables.ts

// Create bill from goods receipt
export const createPurchaseBill = async (
  goodsReceiptId: string,
  billData: {
    supplierInvoiceNumber?: string;
    billDate?: Date;
    notes?: string;
  }
): Promise<PurchaseBill> => {
  const receipt = await prisma.goodsReceipt.findUnique({
    where: { id: goodsReceiptId },
    include: {
      supplier: { include: { payable: true } },
      items: true
    }
  });

  const payable = receipt.supplier.payable;
  const billNumber = await generateBillNumber();

  const subtotal = receipt.items.reduce((sum, item) =>
    sum + Number(item.quantity) * Number(item.unitCost), 0
  );
  const tax = subtotal * 0.1; // 10% VAT
  const total = subtotal + tax;

  const dueDate = addDays(
    billData.billDate || new Date(),
    payable?.paymentTermDays || 30
  );

  const bill = await prisma.purchaseBill.create({
    data: {
      billNumber,
      supplierId: receipt.supplierId,
      payableId: payable.id,
      goodsReceiptId,
      subtotal,
      tax,
      total,
      balance: total,
      billDate: billData.billDate || new Date(),
      dueDate,
      supplierInvoiceNumber: billData.supplierInvoiceNumber,
      notes: billData.notes,
      status: 'PENDING'
    }
  });

  // Update payable balance
  await prisma.supplierPayable.update({
    where: { id: payable.id },
    data: {
      totalPayable: { increment: total }
    }
  });

  return bill;
};

// Pay bill
export const payBill = async (
  billId: string,
  payment: {
    amount: number;
    method: PaymentMethod;
    bankAccount?: string;
    referenceNumber?: string;
    notes?: string;
  },
  paidBy: string
): Promise<PurchaseBill> => {
  const bill = await prisma.purchaseBill.findUnique({
    where: { id: billId },
    include: { payable: true }
  });

  if (payment.amount > Number(bill.balance)) {
    throw new Error('Payment exceeds bill balance');
  }

  const newBalance = Number(bill.balance) - payment.amount;
  const newPaidAmount = Number(bill.paidAmount) + payment.amount;

  // Check early payment discount
  let discountAmount = 0;
  if (bill.payable.earlyPaymentDays && bill.payable.earlyPaymentDiscount) {
    const daysSinceBill = differenceInDays(new Date(), bill.billDate);
    if (daysSinceBill <= bill.payable.earlyPaymentDays) {
      discountAmount = payment.amount * Number(bill.payable.earlyPaymentDiscount) / 100;
    }
  }

  // Record payment
  await prisma.billPayment.create({
    data: {
      billId,
      amount: payment.amount - discountAmount,
      method: payment.method,
      bankAccount: payment.bankAccount,
      referenceNumber: payment.referenceNumber,
      notes: payment.notes,
      paidBy,
      paymentDate: new Date()
    }
  });

  // Update bill
  const actualPayment = payment.amount - discountAmount;
  const updatedBill = await prisma.purchaseBill.update({
    where: { id: billId },
    data: {
      paidAmount: newPaidAmount,
      balance: { decrement: actualPayment },
      status: newBalance <= 0 ? 'PAID' : 'PARTIAL',
      paidDate: newBalance <= 0 ? new Date() : undefined
    }
  });

  // Update payable balance
  await prisma.supplierPayable.update({
    where: { id: bill.payableId },
    data: {
      totalPayable: { decrement: actualPayment }
    }
  });

  return updatedBill;
};

// Schedule payment batch
export const schedulePayments = async (
  bills: { billId: string; amount: number }[],
  scheduledDate: Date
): Promise<PaymentSchedule> => {
  // Group by supplier
  const billsWithSupplier = await Promise.all(
    bills.map(async b => {
      const bill = await prisma.purchaseBill.findUnique({
        where: { id: b.billId },
        select: { id: true, billNumber: true, supplierId: true, balance: true }
      });
      return { ...b, bill };
    })
  );

  const bySupplier = groupBy(billsWithSupplier, 'bill.supplierId');

  const schedules: PaymentSchedule[] = [];

  for (const [supplierId, supplierBills] of Object.entries(bySupplier)) {
    const schedule = await prisma.paymentSchedule.create({
      data: {
        supplierId,
        scheduledDate,
        totalAmount: supplierBills.reduce((sum, b) => sum + b.amount, 0),
        status: 'SCHEDULED',
        bills: {
          create: supplierBills.map(b => ({
            billId: b.billId,
            billNumber: b.bill.billNumber,
            amount: b.amount,
            isPartial: b.amount < Number(b.bill.balance)
          }))
        }
      }
    });
    schedules.push(schedule);
  }

  return schedules;
};
```

## Components

### SupplierPayableSummary

```tsx
const SupplierPayableSummary = ({ payable }: { payable: SupplierPayable }) => (
  <Card>
    <CardHeader>
      <CardTitle className="text-lg">{payable.supplierName}</CardTitle>
    </CardHeader>
    <CardContent>
      <div className="grid grid-cols-3 gap-4">
        <div>
          <p className="text-sm text-muted-foreground">Total Payable</p>
          <p className="text-xl font-bold">{formatCurrency(payable.totalPayable)}</p>
        </div>
        <div>
          <p className="text-sm text-muted-foreground">Overdue</p>
          <p className={cn(
            "text-xl font-bold",
            payable.overdueAmount > 0 ? "text-red-600" : "text-green-600"
          )}>
            {formatCurrency(payable.overdueAmount)}
          </p>
        </div>
        <div>
          <p className="text-sm text-muted-foreground">Payment Terms</p>
          <p className="text-xl font-bold">Net {payable.paymentTermDays}</p>
        </div>
      </div>

      {payable.earlyPaymentDiscount && (
        <div className="mt-4 p-3 bg-green-50 rounded text-sm">
          <span className="font-medium text-green-700">
            {payable.earlyPaymentDiscount.discountPercent}% discount
          </span>
          {' '}if paid within {payable.earlyPaymentDiscount.days} days
        </div>
      )}
    </CardContent>
  </Card>
);
```

### PaymentScheduler

```tsx
const PaymentScheduler = () => {
  const [selectedBills, setSelectedBills] = useState<Map<string, number>>(new Map());
  const [scheduledDate, setScheduledDate] = useState<Date>(new Date());

  const { data: dueBills } = useQuery({
    queryKey: ['due-bills'],
    queryFn: () => fetch('/api/debt/bills?status=pending,overdue').then(r => r.json())
  });

  const { mutate: schedule } = useMutation({
    mutationFn: () => fetch('/api/debt/payment-schedules', {
      method: 'POST',
      body: JSON.stringify({
        bills: Array.from(selectedBills.entries()).map(([billId, amount]) => ({
          billId,
          amount
        })),
        scheduledDate
      })
    })
  });

  const totalSelected = Array.from(selectedBills.values()).reduce((a, b) => a + b, 0);

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-bold">Schedule Payments</h2>
        <div className="flex items-center gap-4">
          <div>
            <Label>Payment Date</Label>
            <DatePicker
              selected={scheduledDate}
              onSelect={setScheduledDate}
            />
          </div>
          <Button onClick={() => schedule()} disabled={selectedBills.size === 0}>
            Schedule ({formatCurrency(totalSelected)})
          </Button>
        </div>
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className="w-12">
              <Checkbox
                checked={selectedBills.size === dueBills?.length}
                onCheckedChange={(checked) => {
                  if (checked) {
                    const all = new Map(dueBills.map(b => [b.id, b.balance]));
                    setSelectedBills(all);
                  } else {
                    setSelectedBills(new Map());
                  }
                }}
              />
            </TableHead>
            <TableHead>Supplier</TableHead>
            <TableHead>Bill #</TableHead>
            <TableHead>Due Date</TableHead>
            <TableHead className="text-right">Balance</TableHead>
            <TableHead className="text-right">Pay Amount</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {dueBills?.map((bill: PurchaseBill) => (
            <TableRow key={bill.id}>
              <TableCell>
                <Checkbox
                  checked={selectedBills.has(bill.id)}
                  onCheckedChange={(checked) => {
                    const newMap = new Map(selectedBills);
                    if (checked) {
                      newMap.set(bill.id, bill.balance);
                    } else {
                      newMap.delete(bill.id);
                    }
                    setSelectedBills(newMap);
                  }}
                />
              </TableCell>
              <TableCell>{bill.supplierName}</TableCell>
              <TableCell>{bill.billNumber}</TableCell>
              <TableCell>
                <span className={cn(
                  isPast(bill.dueDate) && "text-red-600"
                )}>
                  {formatDate(bill.dueDate)}
                </span>
              </TableCell>
              <TableCell className="text-right">
                {formatCurrency(bill.balance)}
              </TableCell>
              <TableCell className="text-right">
                {selectedBills.has(bill.id) && (
                  <Input
                    type="number"
                    value={selectedBills.get(bill.id)}
                    onChange={(e) => {
                      const newMap = new Map(selectedBills);
                      newMap.set(bill.id, Math.min(Number(e.target.value), bill.balance));
                      setSelectedBills(newMap);
                    }}
                    className="w-32 text-right"
                  />
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
};
```

## Cash Flow Projection

```typescript
interface CashFlowProjection {
  date: Date;
  payables: number;           // Due payments
  receivables: number;        // Expected receipts
  netFlow: number;
  runningBalance: number;
}

export const projectCashFlow = async (days: number): Promise<CashFlowProjection[]> => {
  const today = new Date();
  const endDate = addDays(today, days);

  // Get all due payables
  const payables = await prisma.purchaseBill.findMany({
    where: {
      status: { in: ['PENDING', 'PARTIAL', 'OVERDUE'] },
      dueDate: { gte: today, lte: endDate }
    },
    select: { dueDate: true, balance: true }
  });

  // Get all due receivables
  const receivables = await prisma.invoice.findMany({
    where: {
      status: { in: ['SENT', 'PARTIAL', 'OVERDUE'] },
      dueDate: { gte: today, lte: endDate }
    },
    select: { dueDate: true, balance: true }
  });

  // Group by date
  const projections: CashFlowProjection[] = [];
  let runningBalance = await getCurrentCashBalance();

  for (let d = 0; d < days; d++) {
    const date = addDays(today, d);
    const dateStr = format(date, 'yyyy-MM-dd');

    const dayPayables = payables
      .filter(p => format(p.dueDate, 'yyyy-MM-dd') === dateStr)
      .reduce((sum, p) => sum + Number(p.balance), 0);

    const dayReceivables = receivables
      .filter(r => format(r.dueDate, 'yyyy-MM-dd') === dateStr)
      .reduce((sum, r) => sum + Number(r.balance), 0);

    const netFlow = dayReceivables - dayPayables;
    runningBalance += netFlow;

    projections.push({
      date,
      payables: dayPayables,
      receivables: dayReceivables,
      netFlow,
      runningBalance
    });
  }

  return projections;
};
```
