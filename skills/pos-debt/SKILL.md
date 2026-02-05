---
name: pos-debt
description: |
  Manage customer and supplier debt for POS systems: customer credit (credit limits, payment
  terms, outstanding balance), supplier payables (purchase invoices, payment scheduling),
  debt aging (30/60/90 day reports), payment collection (reminders, partial payments),
  credit risk (scoring, limits). Use when implementing credit sales, managing accounts
  receivable/payable, or building debt tracking for wholesale/B2B POS.
version: 1.0.0
---

# POS Debt & Credit Management

Quản lý công nợ khách hàng và nhà cung cấp cho hệ thống POS.

## Debt Features

### 1. Customer Credit (Accounts Receivable)
Reference: [references/customer-credit.md](references/customer-credit.md)
- Credit limits and terms
- Outstanding balance tracking
- Payment history
- Credit applications

### 2. Supplier Payables (Accounts Payable)
Reference: [references/supplier-payables.md](references/supplier-payables.md)
- Purchase invoice tracking
- Payment scheduling
- Supplier statements
- Early payment discounts

### 3. Debt Aging Reports
Reference: [references/debt-aging.md](references/debt-aging.md)
- 30/60/90+ day aging analysis
- Overdue notifications
- Collection priority

### 4. Payment Collection
Reference: [references/payment-collection.md](references/payment-collection.md)
- Payment reminders (SMS, email)
- Partial payment handling
- Payment plans
- Collection workflows

### 5. Credit Risk Management
Reference: [references/credit-risk.md](references/credit-risk.md)
- Credit scoring
- Limit recommendations
- Risk alerts

## Data Models

```typescript
interface DebtAccount {
  id: string;
  type: 'customer' | 'supplier';
  entityId: string;          // Customer or Supplier ID
  entityName: string;

  // Credit terms
  creditLimit: number;
  paymentTermDays: number;   // Net 30, Net 60, etc.

  // Balances
  totalDebt: number;
  current: number;           // Not yet due
  overdue30: number;
  overdue60: number;
  overdue90: number;

  // Status
  status: DebtStatus;
  riskLevel: RiskLevel;
  lastPaymentAt?: Date;
  nextDueDate?: Date;
}

type DebtStatus = 'current' | 'overdue' | 'delinquent' | 'collections' | 'written_off';
type RiskLevel = 'low' | 'medium' | 'high';

interface DebtTransaction {
  id: string;
  accountId: string;
  type: 'invoice' | 'payment' | 'credit_note' | 'adjustment';
  referenceId: string;       // Order ID or Payment ID
  referenceNumber: string;
  amount: number;
  balance: number;           // Running balance
  dueDate?: Date;
  paidDate?: Date;
  notes?: string;
  createdAt: Date;
}

interface PaymentPlan {
  id: string;
  accountId: string;
  totalAmount: number;
  installments: number;
  installmentAmount: number;
  frequency: 'weekly' | 'biweekly' | 'monthly';
  startDate: Date;
  status: 'active' | 'completed' | 'defaulted';
  payments: PaymentPlanItem[];
}

interface PaymentPlanItem {
  dueDate: Date;
  amount: number;
  status: 'pending' | 'paid' | 'overdue';
  paidAt?: Date;
  paidAmount?: number;
}
```

## Components

```
components/debt/
├── DebtDashboard.tsx         # Overview with aging chart
├── CustomerDebt.tsx          # Customer debt management
├── SupplierDebt.tsx          # Supplier payables
├── DebtAgingTable.tsx        # Aging analysis table
├── CreditLimitForm.tsx       # Set/adjust credit limits
├── PaymentReceiptModal.tsx   # Record payment
├── PaymentPlanBuilder.tsx    # Create payment plans
├── DebtReminder.tsx          # Send reminders
├── CreditApplication.tsx     # Customer credit request
├── StatementGenerator.tsx    # Generate statements
└── CollectionWorkflow.tsx    # Collection process
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/debt/dashboard` | Debt overview |
| GET | `/api/debt/customers` | Customer debts |
| GET | `/api/debt/customers/:id` | Customer debt detail |
| GET | `/api/debt/suppliers` | Supplier payables |
| GET | `/api/debt/aging` | Aging report |
| POST | `/api/debt/payments` | Record payment |
| POST | `/api/debt/payment-plans` | Create payment plan |
| POST | `/api/debt/reminders` | Send reminders |
| PUT | `/api/debt/credit-limits/:id` | Adjust credit limit |
| GET | `/api/debt/statements/:id` | Generate statement |

## Credit Terms Configuration

```typescript
const creditTerms = {
  // Default terms
  defaultLimit: 5000000,      // 5M VND
  defaultTermDays: 30,        // Net 30

  // Credit tiers
  tiers: [
    { name: 'Standard', limit: 5000000, termDays: 30 },
    { name: 'Silver', limit: 20000000, termDays: 45 },
    { name: 'Gold', limit: 50000000, termDays: 60 },
    { name: 'Platinum', limit: 100000000, termDays: 90 }
  ],

  // Early payment discounts
  earlyPaymentDiscount: {
    days: 10,
    discountPercent: 2      // 2% discount if paid within 10 days
  },

  // Late payment penalties
  lateFee: {
    type: 'percentage',
    value: 1,               // 1% per month
    gracePeriodDays: 7
  }
};
```

## Aging Calculation

```typescript
const calculateAging = (transactions: DebtTransaction[]): AgingBuckets => {
  const today = new Date();
  const aging = { current: 0, overdue30: 0, overdue60: 0, overdue90: 0 };

  transactions
    .filter(t => t.type === 'invoice' && !t.paidDate)
    .forEach(t => {
      const daysPastDue = differenceInDays(today, t.dueDate);

      if (daysPastDue <= 0) aging.current += t.balance;
      else if (daysPastDue <= 30) aging.overdue30 += t.balance;
      else if (daysPastDue <= 60) aging.overdue60 += t.balance;
      else aging.overdue90 += t.balance;
    });

  return aging;
};
```

## Collection Workflow

```typescript
const collectionWorkflow = [
  { daysPastDue: 1, action: 'email_reminder', template: 'friendly_reminder' },
  { daysPastDue: 7, action: 'sms_reminder', template: 'payment_due' },
  { daysPastDue: 14, action: 'phone_call', assignTo: 'collections_team' },
  { daysPastDue: 30, action: 'formal_notice', template: 'overdue_notice' },
  { daysPastDue: 60, action: 'collections_agency', escalate: true },
  { daysPastDue: 90, action: 'legal_review', escalate: true }
];
```
