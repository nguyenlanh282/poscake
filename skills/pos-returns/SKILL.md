---
name: pos-returns
description: |
  Handle product returns and refunds for POS systems: return policies (time limits, conditions),
  return authorization (RMA), refund processing (original payment, store credit, exchange),
  inventory adjustment (restock, damaged goods), return analytics (return rate, reasons).
  Use when implementing return flows, processing refunds, or managing RMA for retail POS.
version: 1.0.0
---

# POS Returns & Refunds

Xử lý đổi trả hàng và hoàn tiền cho hệ thống POS.

## Return Features

### 1. Return Policies
Reference: [references/return-policies.md](references/return-policies.md)
- Time limits (7/14/30 days)
- Condition requirements (tags, packaging)
- Product exclusions
- Receipt requirements

### 2. Return Authorization (RMA)
Reference: [references/rma.md](references/rma.md)
- Return request creation
- Approval workflow
- Return shipping labels
- RMA tracking

### 3. Refund Processing
Reference: [references/refunds.md](references/refunds.md)
- Original payment method
- Store credit/voucher
- Exchange for different product
- Partial refunds

### 4. Inventory Adjustment
Reference: [references/inventory-adjustment.md](references/inventory-adjustment.md)
- Restock to inventory
- Mark as damaged/defective
- Quality inspection workflow

### 5. Return Analytics
Reference: [references/return-analytics.md](references/return-analytics.md)
- Return rate by product/category
- Top return reasons
- Return cost analysis

## Data Models

```typescript
interface Return {
  id: string;
  returnNumber: string;      // RMA-2024-0001
  orderId: string;
  orderNumber: string;
  customerId: string;

  // Return details
  status: ReturnStatus;
  type: ReturnType;
  reason: ReturnReason;
  reasonDetail?: string;

  // Items
  items: ReturnItem[];

  // Refund
  refundMethod: RefundMethod;
  refundAmount: number;
  refundStatus: RefundStatus;

  // Dates
  requestedAt: Date;
  approvedAt?: Date;
  receivedAt?: Date;
  completedAt?: Date;

  // Staff
  approvedBy?: string;
  processedBy?: string;
  notes?: string;
}

type ReturnStatus = 'pending' | 'approved' | 'rejected' | 'received' | 'processing' | 'completed' | 'cancelled';
type ReturnType = 'refund' | 'exchange' | 'store_credit';
type ReturnReason = 'defective' | 'wrong_item' | 'not_as_described' | 'changed_mind' | 'damaged_shipping' | 'size_issue' | 'other';
type RefundMethod = 'original_payment' | 'store_credit' | 'bank_transfer' | 'cash';
type RefundStatus = 'pending' | 'processing' | 'completed' | 'failed';

interface ReturnItem {
  id: string;
  orderItemId: string;
  productId: string;
  productName: string;
  variantName?: string;
  quantity: number;
  unitPrice: number;
  reason: ReturnReason;
  condition: ItemCondition;
  action: ItemAction;
}

type ItemCondition = 'new' | 'opened' | 'used' | 'damaged' | 'defective';
type ItemAction = 'restock' | 'damaged' | 'dispose' | 'vendor_return';
```

## Components

```
components/returns/
├── ReturnDashboard.tsx       # Returns overview
├── CreateReturn.tsx          # New return form
├── ReturnLookup.tsx          # Find order for return
├── ReturnItemSelector.tsx    # Select items to return
├── ReasonSelector.tsx        # Return reason selection
├── RefundCalculator.tsx      # Calculate refund amount
├── RefundMethodSelector.tsx  # Choose refund method
├── ReturnApproval.tsx        # Approve/reject returns
├── ReturnReceive.tsx         # Mark items received
├── ReturnProcess.tsx         # Process refund
├── ExchangeSelector.tsx      # Select exchange items
└── ReturnHistory.tsx         # Customer return history
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/returns` | Create return |
| GET | `/api/returns` | List returns |
| GET | `/api/returns/:id` | Return details |
| PUT | `/api/returns/:id/approve` | Approve return |
| PUT | `/api/returns/:id/reject` | Reject return |
| PUT | `/api/returns/:id/receive` | Mark received |
| POST | `/api/returns/:id/refund` | Process refund |
| GET | `/api/returns/analytics` | Return analytics |
| GET | `/api/orders/:id/returnable` | Get returnable items |

## Return Policy Configuration

```typescript
const returnPolicy = {
  // Time limits
  returnWindowDays: 30,
  exchangeWindowDays: 60,

  // Conditions
  requireReceipt: true,
  requireOriginalPackaging: false,
  requireTags: true,

  // Excluded categories
  excludedCategories: ['food', 'personal_care', 'underwear', 'clearance'],

  // Restocking fee
  restockingFee: {
    enabled: true,
    percentage: 15,
    exemptReasons: ['defective', 'wrong_item', 'damaged_shipping']
  },

  // Refund methods by original payment
  refundMethods: {
    cash: ['cash', 'store_credit'],
    card: ['original_payment', 'store_credit'],
    e_wallet: ['original_payment', 'store_credit'],
    bank_transfer: ['bank_transfer', 'store_credit']
  }
};
```

## Return Processing Flow

```typescript
const returnFlow = {
  steps: [
    { status: 'pending', action: 'Customer submits return request' },
    { status: 'approved', action: 'Staff reviews and approves' },
    { status: 'received', action: 'Items received at store/warehouse' },
    { status: 'processing', action: 'Quality inspection, inventory update' },
    { status: 'completed', action: 'Refund processed' }
  ],

  autoApprove: {
    enabled: true,
    conditions: [
      { field: 'orderAge', operator: 'lte', value: 7 },
      { field: 'customerTier', operator: 'in', value: ['gold', 'platinum'] },
      { field: 'returnCount', operator: 'lte', value: 2 }
    ]
  }
};
```

## Refund Calculation

```typescript
const calculateRefund = (returnItems: ReturnItem[], policy: ReturnPolicy): RefundCalculation => {
  let subtotal = returnItems.reduce((sum, item) => sum + (item.quantity * item.unitPrice), 0);

  // Apply restocking fee if applicable
  let restockingFee = 0;
  if (policy.restockingFee.enabled) {
    const chargeableItems = returnItems.filter(
      item => !policy.restockingFee.exemptReasons.includes(item.reason)
    );
    const chargeableAmount = chargeableItems.reduce(
      (sum, item) => sum + (item.quantity * item.unitPrice), 0
    );
    restockingFee = chargeableAmount * (policy.restockingFee.percentage / 100);
  }

  return {
    subtotal,
    restockingFee,
    total: subtotal - restockingFee
  };
};
```
