# Customer Credit (Accounts Receivable)

Quản lý công nợ khách hàng - cho phép khách mua hàng trả sau.

## Overview

Customer credit cho phép khách hàng B2B hoặc VIP mua hàng và thanh toán sau theo thỏa thuận tín dụng.

## Data Model

```typescript
interface CustomerCredit {
  customerId: string;
  customerName: string;

  // Credit terms
  creditLimit: number;
  paymentTermDays: number;    // Net 30, Net 60, etc.
  creditTier: CreditTier;

  // Balances
  totalOutstanding: number;   // Total unpaid
  availableCredit: number;    // Limit - Outstanding
  overdueAmount: number;

  // Status
  status: CreditStatus;
  creditScore?: number;       // Internal score
  lastReviewDate?: Date;
  nextReviewDate?: Date;

  // History
  totalCreditUsed: number;    // Lifetime
  avgPaymentDays: number;     // Average days to pay
  latePaymentCount: number;
}

type CreditTier = 'standard' | 'silver' | 'gold' | 'platinum';
type CreditStatus = 'active' | 'suspended' | 'frozen' | 'closed';

interface Invoice {
  id: string;
  invoiceNumber: string;      // INV-2024-0001
  customerId: string;
  orderId: string;

  // Amounts
  subtotal: number;
  tax: number;
  total: number;
  paidAmount: number;
  balance: number;            // Total - Paid

  // Dates
  invoiceDate: Date;
  dueDate: Date;
  paidDate?: Date;

  // Status
  status: InvoiceStatus;
  paymentTerms: string;       // "Net 30"

  // Payments
  payments: InvoicePayment[];
}

type InvoiceStatus = 'draft' | 'sent' | 'partial' | 'paid' | 'overdue' | 'written_off';

interface InvoicePayment {
  id: string;
  amount: number;
  method: PaymentMethod;
  referenceNumber?: string;
  receivedAt: Date;
  receivedBy: string;
  notes?: string;
}
```

## Database Schema

```prisma
model CustomerCredit {
  id                String   @id @default(cuid())
  customerId        String   @unique
  customer          Customer @relation(fields: [customerId], references: [id])

  creditLimit       Decimal
  paymentTermDays   Int      @default(30)
  creditTier        CreditTier @default(STANDARD)

  totalOutstanding  Decimal  @default(0)
  availableCredit   Decimal
  overdueAmount     Decimal  @default(0)

  status            CreditStatus @default(ACTIVE)
  creditScore       Int?
  lastReviewDate    DateTime?
  nextReviewDate    DateTime?

  // Stats
  totalCreditUsed   Decimal  @default(0)
  avgPaymentDays    Float    @default(0)
  latePaymentCount  Int      @default(0)

  createdAt         DateTime @default(now())
  updatedAt         DateTime @updatedAt

  invoices          Invoice[]
}

model Invoice {
  id              String   @id @default(cuid())
  invoiceNumber   String   @unique
  customerId      String
  orderId         String   @unique
  creditId        String

  subtotal        Decimal
  tax             Decimal  @default(0)
  total           Decimal
  paidAmount      Decimal  @default(0)
  balance         Decimal

  invoiceDate     DateTime @default(now())
  dueDate         DateTime
  paidDate        DateTime?

  status          InvoiceStatus @default(SENT)
  paymentTerms    String

  credit          CustomerCredit @relation(fields: [creditId], references: [id])
  payments        InvoicePayment[]

  @@index([customerId])
  @@index([status])
  @@index([dueDate])
}

enum CreditTier {
  STANDARD
  SILVER
  GOLD
  PLATINUM
}

enum CreditStatus {
  ACTIVE
  SUSPENDED
  FROZEN
  CLOSED
}

enum InvoiceStatus {
  DRAFT
  SENT
  PARTIAL
  PAID
  OVERDUE
  WRITTEN_OFF
}
```

## Service Implementation

```typescript
// services/customerCredit.ts

// Check if customer can make a credit purchase
export const checkCreditAvailability = async (
  customerId: string,
  orderAmount: number
): Promise<{ available: boolean; reason?: string }> => {
  const credit = await prisma.customerCredit.findUnique({
    where: { customerId }
  });

  if (!credit) {
    return { available: false, reason: 'No credit account' };
  }

  if (credit.status !== 'ACTIVE') {
    return { available: false, reason: `Credit account is ${credit.status}` };
  }

  if (credit.overdueAmount > 0) {
    return { available: false, reason: 'Has overdue invoices' };
  }

  if (orderAmount > Number(credit.availableCredit)) {
    return {
      available: false,
      reason: `Order exceeds available credit (${formatCurrency(credit.availableCredit)})`
    };
  }

  return { available: true };
};

// Create credit sale
export const createCreditSale = async (
  orderId: string
): Promise<Invoice> => {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { customer: { include: { credit: true } } }
  });

  const credit = order.customer.credit;
  if (!credit) throw new Error('Customer has no credit account');

  const invoiceNumber = await generateInvoiceNumber();
  const dueDate = addDays(new Date(), credit.paymentTermDays);

  // Create invoice
  const invoice = await prisma.invoice.create({
    data: {
      invoiceNumber,
      customerId: order.customerId,
      orderId,
      creditId: credit.id,
      subtotal: order.subtotal,
      tax: order.tax,
      total: order.totalAmount,
      balance: order.totalAmount,
      dueDate,
      paymentTerms: `Net ${credit.paymentTermDays}`,
      status: 'SENT'
    }
  });

  // Update credit balance
  await prisma.customerCredit.update({
    where: { id: credit.id },
    data: {
      totalOutstanding: { increment: order.totalAmount },
      availableCredit: { decrement: order.totalAmount },
      totalCreditUsed: { increment: order.totalAmount }
    }
  });

  return invoice;
};

// Record payment against invoice
export const recordInvoicePayment = async (
  invoiceId: string,
  payment: {
    amount: number;
    method: PaymentMethod;
    referenceNumber?: string;
    notes?: string;
  },
  receivedBy: string
): Promise<Invoice> => {
  const invoice = await prisma.invoice.findUnique({
    where: { id: invoiceId },
    include: { credit: true }
  });

  if (payment.amount > Number(invoice.balance)) {
    throw new Error('Payment exceeds invoice balance');
  }

  const newBalance = Number(invoice.balance) - payment.amount;
  const newPaidAmount = Number(invoice.paidAmount) + payment.amount;

  // Create payment record
  await prisma.invoicePayment.create({
    data: {
      invoiceId,
      amount: payment.amount,
      method: payment.method,
      referenceNumber: payment.referenceNumber,
      notes: payment.notes,
      receivedBy,
      receivedAt: new Date()
    }
  });

  // Update invoice
  const updatedInvoice = await prisma.invoice.update({
    where: { id: invoiceId },
    data: {
      paidAmount: newPaidAmount,
      balance: newBalance,
      status: newBalance === 0 ? 'PAID' : 'PARTIAL',
      paidDate: newBalance === 0 ? new Date() : undefined
    }
  });

  // Update credit balance
  await prisma.customerCredit.update({
    where: { id: invoice.creditId },
    data: {
      totalOutstanding: { decrement: payment.amount },
      availableCredit: { increment: payment.amount }
    }
  });

  // Update payment stats if fully paid
  if (newBalance === 0) {
    const daysToPayment = differenceInDays(new Date(), invoice.invoiceDate);
    const wasLate = daysToPayment > invoice.credit.paymentTermDays;

    await updatePaymentStats(invoice.creditId, daysToPayment, wasLate);
  }

  return updatedInvoice;
};
```

## Credit Application

```typescript
interface CreditApplication {
  id: string;
  customerId: string;
  requestedLimit: number;
  requestedTermDays: number;

  // Business info
  businessName: string;
  businessType: string;
  yearsInBusiness: number;
  annualRevenue?: number;
  taxId?: string;

  // References
  tradeReferences: TradeReference[];
  bankReference?: BankReference;

  // Status
  status: ApplicationStatus;
  reviewedBy?: string;
  reviewNotes?: string;
  approvedLimit?: number;
  approvedTermDays?: number;

  createdAt: Date;
  reviewedAt?: Date;
}

type ApplicationStatus = 'pending' | 'under_review' | 'approved' | 'rejected';

interface TradeReference {
  companyName: string;
  contactName: string;
  phone: string;
  email: string;
}

// Approve credit application
export const approveCreditApplication = async (
  applicationId: string,
  approval: {
    limit: number;
    termDays: number;
    tier: CreditTier;
    notes?: string;
  },
  reviewedBy: string
) => {
  const application = await prisma.creditApplication.update({
    where: { id: applicationId },
    data: {
      status: 'APPROVED',
      approvedLimit: approval.limit,
      approvedTermDays: approval.termDays,
      reviewedBy,
      reviewNotes: approval.notes,
      reviewedAt: new Date()
    }
  });

  // Create credit account
  await prisma.customerCredit.create({
    data: {
      customerId: application.customerId,
      creditLimit: approval.limit,
      paymentTermDays: approval.termDays,
      creditTier: approval.tier,
      availableCredit: approval.limit,
      status: 'ACTIVE'
    }
  });

  // Notify customer
  await sendNotification(application.customerId, {
    type: 'credit_approved',
    title: 'Credit Application Approved',
    body: `Your credit account has been approved with a limit of ${formatCurrency(approval.limit)}.`
  });
};
```

## Components

### CustomerCreditCard

```tsx
const CustomerCreditCard = ({ credit }: { credit: CustomerCredit }) => {
  const utilizationPercent = (credit.totalOutstanding / credit.creditLimit) * 100;

  return (
    <Card>
      <CardHeader>
        <div className="flex justify-between items-center">
          <CardTitle>Credit Account</CardTitle>
          <CreditStatusBadge status={credit.status} />
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Utilization */}
        <div>
          <div className="flex justify-between text-sm mb-1">
            <span>Credit Utilization</span>
            <span>{utilizationPercent.toFixed(0)}%</span>
          </div>
          <Progress
            value={utilizationPercent}
            className={cn(
              "h-2",
              utilizationPercent > 80 && "bg-red-200 [&>div]:bg-red-500"
            )}
          />
        </div>

        {/* Balances */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <p className="text-sm text-muted-foreground">Credit Limit</p>
            <p className="text-lg font-semibold">{formatCurrency(credit.creditLimit)}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Available</p>
            <p className="text-lg font-semibold text-green-600">
              {formatCurrency(credit.availableCredit)}
            </p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Outstanding</p>
            <p className="text-lg font-semibold">{formatCurrency(credit.totalOutstanding)}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Overdue</p>
            <p className={cn(
              "text-lg font-semibold",
              credit.overdueAmount > 0 ? "text-red-600" : "text-muted-foreground"
            )}>
              {formatCurrency(credit.overdueAmount)}
            </p>
          </div>
        </div>

        {/* Terms */}
        <div className="flex justify-between pt-4 border-t">
          <div>
            <p className="text-sm text-muted-foreground">Payment Terms</p>
            <p className="font-medium">Net {credit.paymentTermDays}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Credit Tier</p>
            <CreditTierBadge tier={credit.creditTier} />
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
```

### InvoiceList

```tsx
const InvoiceList = ({ customerId }: { customerId: string }) => {
  const { data: invoices, isLoading } = useQuery({
    queryKey: ['customer-invoices', customerId],
    queryFn: () => fetch(`/api/debt/customers/${customerId}/invoices`).then(r => r.json())
  });

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Invoice #</TableHead>
          <TableHead>Date</TableHead>
          <TableHead>Due Date</TableHead>
          <TableHead className="text-right">Total</TableHead>
          <TableHead className="text-right">Balance</TableHead>
          <TableHead>Status</TableHead>
          <TableHead></TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {invoices?.map((invoice: Invoice) => (
          <TableRow key={invoice.id}>
            <TableCell className="font-medium">{invoice.invoiceNumber}</TableCell>
            <TableCell>{formatDate(invoice.invoiceDate)}</TableCell>
            <TableCell>{formatDate(invoice.dueDate)}</TableCell>
            <TableCell className="text-right">{formatCurrency(invoice.total)}</TableCell>
            <TableCell className="text-right">{formatCurrency(invoice.balance)}</TableCell>
            <TableCell>
              <InvoiceStatusBadge status={invoice.status} />
            </TableCell>
            <TableCell>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="sm">
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent>
                  <DropdownMenuItem>View Details</DropdownMenuItem>
                  <DropdownMenuItem>Record Payment</DropdownMenuItem>
                  <DropdownMenuItem>Print Invoice</DropdownMenuItem>
                  <DropdownMenuItem>Send Reminder</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
};
```
