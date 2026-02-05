# Refund Processing

Xử lý hoàn tiền qua các phương thức khác nhau.

## Overview

Refund processing xử lý việc hoàn tiền cho khách hàng qua original payment method, store credit, hoặc các phương thức khác.

## Data Model

```typescript
interface Refund {
  id: string;
  refundNumber: string;        // REF-2024-0001

  // References
  rmaId: string;
  orderId: string;
  customerId: string;

  // Amounts
  itemsAmount: number;         // Sum of returned items
  shippingAmount: number;      // Shipping refund
  restockingFee: number;       // Deducted fee
  adjustments: number;         // Manual adjustments
  totalAmount: number;         // Final refund amount

  // Method
  method: RefundMethod;
  destination: RefundDestination;

  // Status
  status: RefundStatus;
  failureReason?: string;

  // Payment details
  originalPaymentId?: string;
  originalPaymentMethod?: PaymentMethod;
  transactionId?: string;
  storeCreditId?: string;

  // Dates
  requestedAt: Date;
  processedAt?: Date;
  completedAt?: Date;

  // Staff
  processedBy?: string;
  approvedBy?: string;
  notes?: string;
}

type RefundMethod = 'original_payment' | 'store_credit' | 'bank_transfer' | 'cash';
type RefundStatus = 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled';

interface RefundDestination {
  type: 'card' | 'bank' | 'wallet' | 'store_credit' | 'cash';
  details: string;             // Last 4 digits, bank name, etc.
}

interface StoreCredit {
  id: string;
  code: string;                // SC-XXXXXX
  customerId: string;
  originalAmount: number;
  balance: number;
  rmaId?: string;
  expiresAt?: Date;
  status: 'active' | 'used' | 'expired' | 'cancelled';
  createdAt: Date;
}
```

## Refund Calculation

```typescript
interface RefundCalculation {
  items: RefundItemLine[];
  subtotal: number;
  shippingRefund: number;
  restockingFee: number;
  adjustments: AdjustmentLine[];
  total: number;
  breakdown: RefundBreakdown;
}

interface RefundItemLine {
  itemId: string;
  productName: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  inspectionResult: InspectionResult;
  refundPercent: number;       // 100% for pass, less for partial
}

interface RefundBreakdown {
  toOriginalPayment: number;
  toStoreCredit: number;
  toBankTransfer: number;
  toCash: number;
}

// Calculate refund amount
export const calculateRefund = async (rmaId: string): Promise<RefundCalculation> => {
  const rma = await prisma.rma.findUnique({
    where: { id: rmaId },
    include: {
      items: true,
      order: { include: { payments: true } }
    }
  });

  const policy = await getActiveReturnPolicy();

  // Calculate item refunds
  const items: RefundItemLine[] = rma.items.map(item => {
    // Determine refund percentage based on inspection
    let refundPercent = 100;
    if (item.inspectionResult === 'partial') {
      refundPercent = 50; // Or based on condition
    } else if (item.inspectionResult === 'fail') {
      refundPercent = 0;
    }

    const lineTotal = item.unitPrice * item.quantity * (refundPercent / 100);

    return {
      itemId: item.id,
      productName: item.productName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      lineTotal,
      inspectionResult: item.inspectionResult,
      refundPercent
    };
  });

  const subtotal = items.reduce((sum, item) => sum + item.lineTotal, 0);

  // Shipping refund (if applicable)
  const shippingRefund = shouldRefundShipping(rma) ? rma.order.shippingCost : 0;

  // Restocking fee
  let restockingFee = 0;
  if (policy.restockingFee && !policy.restockingFee.exemptReasons.includes(rma.reason)) {
    restockingFee = subtotal * (policy.restockingFee.value / 100);
  }

  const total = subtotal + shippingRefund - restockingFee;

  // Determine breakdown by original payment
  const breakdown = calculateBreakdown(rma.order.payments, total, rma.type);

  return {
    items,
    subtotal,
    shippingRefund,
    restockingFee,
    adjustments: [],
    total,
    breakdown
  };
};

const shouldRefundShipping = (rma: RMA): boolean => {
  const refundableReasons: ReturnReason[] = ['defective', 'wrong_item', 'damaged_shipping'];
  return refundableReasons.includes(rma.reason);
};
```

## Refund Processing by Method

```typescript
// services/refundProcessing.ts

export const processRefund = async (
  rmaId: string,
  method: RefundMethod,
  processedBy: string
): Promise<Refund> => {
  const calculation = await calculateRefund(rmaId);
  const rma = await prisma.rma.findUnique({
    where: { id: rmaId },
    include: { order: { include: { payments: true } } }
  });

  const refundNumber = await generateRefundNumber();

  // Create refund record
  const refund = await prisma.refund.create({
    data: {
      refundNumber,
      rmaId,
      orderId: rma.orderId,
      customerId: rma.customerId,
      itemsAmount: calculation.subtotal,
      shippingAmount: calculation.shippingRefund,
      restockingFee: calculation.restockingFee,
      totalAmount: calculation.total,
      method,
      status: 'PROCESSING',
      requestedAt: new Date(),
      processedBy
    }
  });

  try {
    // Process based on method
    switch (method) {
      case 'original_payment':
        await processOriginalPaymentRefund(refund, rma.order.payments);
        break;
      case 'store_credit':
        await processStoreCreditRefund(refund, rma.customerId);
        break;
      case 'bank_transfer':
        await processBankTransferRefund(refund, rma.customerId);
        break;
      case 'cash':
        await processCashRefund(refund);
        break;
    }

    await prisma.refund.update({
      where: { id: refund.id },
      data: {
        status: 'COMPLETED',
        completedAt: new Date()
      }
    });

  } catch (error) {
    await prisma.refund.update({
      where: { id: refund.id },
      data: {
        status: 'FAILED',
        failureReason: error.message
      }
    });
    throw error;
  }

  return refund;
};

// Original payment refund
const processOriginalPaymentRefund = async (
  refund: Refund,
  originalPayments: Payment[]
) => {
  // Group by payment method
  for (const payment of originalPayments) {
    const refundAmount = Math.min(payment.amount, refund.totalAmount);

    switch (payment.method) {
      case 'card':
        await refundStripePayment(payment.transactionId, refundAmount);
        break;
      case 'vnpay':
        await refundVNPayPayment(payment.transactionId, refundAmount);
        break;
      case 'momo':
        await refundMomoPayment(payment.transactionId, refundAmount);
        break;
      case 'zalopay':
        await refundZaloPayPayment(payment.transactionId, refundAmount);
        break;
    }
  }
};

// Store credit refund
const processStoreCreditRefund = async (
  refund: Refund,
  customerId: string
) => {
  const creditCode = generateStoreCreditCode();

  const storeCredit = await prisma.storeCredit.create({
    data: {
      code: creditCode,
      customerId,
      originalAmount: refund.totalAmount,
      balance: refund.totalAmount,
      rmaId: refund.rmaId,
      expiresAt: addYears(new Date(), 1),
      status: 'ACTIVE'
    }
  });

  await prisma.refund.update({
    where: { id: refund.id },
    data: { storeCreditId: storeCredit.id }
  });

  // Send store credit email
  await sendStoreCreditEmail(customerId, storeCredit);
};
```

## Payment Gateway Refunds

```typescript
// lib/payments/stripe.ts
import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

export const refundStripePayment = async (
  paymentIntentId: string,
  amount: number
): Promise<Stripe.Refund> => {
  const refund = await stripe.refunds.create({
    payment_intent: paymentIntentId,
    amount: Math.round(amount), // Stripe uses cents
    reason: 'requested_by_customer'
  });

  return refund;
};

// lib/payments/vnpay.ts
export const refundVNPayPayment = async (
  transactionId: string,
  amount: number
): Promise<VNPayRefundResult> => {
  const params = {
    vnp_RequestId: generateRequestId(),
    vnp_Version: '2.1.0',
    vnp_Command: 'refund',
    vnp_TmnCode: process.env.VNPAY_TMN_CODE,
    vnp_TransactionType: '02', // Full refund
    vnp_TxnRef: transactionId,
    vnp_Amount: amount * 100,
    vnp_TransactionDate: format(new Date(), 'yyyyMMddHHmmss'),
    vnp_CreateBy: 'system'
  };

  // Sign and send request
  const signedParams = signVNPayParams(params);
  const response = await fetch(process.env.VNPAY_REFUND_URL, {
    method: 'POST',
    body: new URLSearchParams(signedParams)
  });

  return await response.json();
};
```

## Components

### RefundCalculator

```tsx
const RefundCalculator = ({ rma }: { rma: RMA }) => {
  const { data: calculation } = useQuery({
    queryKey: ['refund-calculation', rma.id],
    queryFn: () => fetch(`/api/returns/${rma.id}/calculate`).then(r => r.json())
  });

  if (!calculation) return <Skeleton className="h-48" />;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Refund Summary</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Items */}
        {calculation.items.map((item: RefundItemLine) => (
          <div key={item.itemId} className="flex justify-between">
            <div>
              <p>{item.productName}</p>
              <p className="text-sm text-muted-foreground">
                {item.quantity} x {formatCurrency(item.unitPrice)}
                {item.refundPercent < 100 && (
                  <span className="text-yellow-600">
                    {' '}({item.refundPercent}% refund)
                  </span>
                )}
              </p>
            </div>
            <span>{formatCurrency(item.lineTotal)}</span>
          </div>
        ))}

        <Separator />

        {/* Subtotal */}
        <div className="flex justify-between">
          <span>Subtotal</span>
          <span>{formatCurrency(calculation.subtotal)}</span>
        </div>

        {/* Shipping */}
        {calculation.shippingRefund > 0 && (
          <div className="flex justify-between">
            <span>Shipping Refund</span>
            <span>{formatCurrency(calculation.shippingRefund)}</span>
          </div>
        )}

        {/* Restocking fee */}
        {calculation.restockingFee > 0 && (
          <div className="flex justify-between text-red-600">
            <span>Restocking Fee</span>
            <span>-{formatCurrency(calculation.restockingFee)}</span>
          </div>
        )}

        <Separator />

        {/* Total */}
        <div className="flex justify-between font-bold text-lg">
          <span>Total Refund</span>
          <span>{formatCurrency(calculation.total)}</span>
        </div>
      </CardContent>
    </Card>
  );
};
```

### RefundMethodSelector

```tsx
const RefundMethodSelector = ({
  rma,
  onSelect
}: {
  rma: RMA;
  onSelect: (method: RefundMethod) => void;
}) => {
  const originalPayment = rma.order.payments[0];

  const methods = [
    {
      id: 'original_payment',
      label: 'Original Payment Method',
      description: `Refund to ${originalPayment.method} ending in ${originalPayment.last4}`,
      icon: CreditCard,
      available: true
    },
    {
      id: 'store_credit',
      label: 'Store Credit',
      description: 'Get instant store credit to use on future purchases',
      icon: Gift,
      available: true,
      bonus: '+ 5% bonus' // Optional incentive
    },
    {
      id: 'bank_transfer',
      label: 'Bank Transfer',
      description: 'Transfer to your bank account',
      icon: Building,
      available: true
    },
    {
      id: 'cash',
      label: 'Cash',
      description: 'Collect cash at store',
      icon: Banknote,
      available: rma.type === 'in_store'
    }
  ];

  return (
    <RadioGroup onValueChange={(v) => onSelect(v as RefundMethod)}>
      {methods.filter(m => m.available).map(method => {
        const Icon = method.icon;
        return (
          <div key={method.id} className="flex items-center space-x-4 p-4 border rounded-lg">
            <RadioGroupItem value={method.id} id={method.id} />
            <Icon className="h-6 w-6 text-muted-foreground" />
            <div className="flex-1">
              <Label htmlFor={method.id} className="font-medium">
                {method.label}
                {method.bonus && (
                  <Badge variant="secondary" className="ml-2">{method.bonus}</Badge>
                )}
              </Label>
              <p className="text-sm text-muted-foreground">{method.description}</p>
            </div>
          </div>
        );
      })}
    </RadioGroup>
  );
};
```

## Store Credit

```typescript
// Use store credit at checkout
export const applyStoreCredit = async (
  creditCode: string,
  orderId: string,
  amount: number
): Promise<{ success: boolean; appliedAmount: number }> => {
  const credit = await prisma.storeCredit.findUnique({
    where: { code: creditCode }
  });

  if (!credit) throw new Error('Invalid store credit code');
  if (credit.status !== 'ACTIVE') throw new Error('Store credit is not active');
  if (credit.expiresAt && credit.expiresAt < new Date()) {
    throw new Error('Store credit has expired');
  }

  const appliedAmount = Math.min(amount, credit.balance);

  await prisma.storeCredit.update({
    where: { id: credit.id },
    data: {
      balance: { decrement: appliedAmount },
      status: credit.balance - appliedAmount <= 0 ? 'USED' : 'ACTIVE'
    }
  });

  // Record usage
  await prisma.storeCreditUsage.create({
    data: {
      storeCreditId: credit.id,
      orderId,
      amount: appliedAmount
    }
  });

  return { success: true, appliedAmount };
};
```
