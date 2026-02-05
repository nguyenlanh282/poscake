# Debt Aging Reports

Phân tích công nợ theo tuổi nợ (30/60/90 ngày).

## Overview

Debt aging report phân loại công nợ theo thời gian quá hạn để ưu tiên thu hồi và đánh giá rủi ro.

## Aging Buckets

```typescript
interface AgingBucket {
  label: string;
  minDays: number;
  maxDays: number;          // null for 90+
  amount: number;
  count: number;
  percentage: number;
}

interface AgingReport {
  type: 'receivable' | 'payable';
  asOfDate: Date;
  totalAmount: number;
  totalCount: number;

  buckets: {
    current: AgingBucket;    // Not yet due
    days1_30: AgingBucket;   // 1-30 days overdue
    days31_60: AgingBucket;  // 31-60 days
    days61_90: AgingBucket;  // 61-90 days
    days90Plus: AgingBucket; // 90+ days
  };

  byCustomer?: CustomerAging[];
  bySupplier?: SupplierAging[];
}

interface CustomerAging {
  customerId: string;
  customerName: string;
  current: number;
  days1_30: number;
  days31_60: number;
  days61_90: number;
  days90Plus: number;
  total: number;
}
```

## SQL Queries

### Customer Aging (Accounts Receivable)

```sql
WITH invoice_aging AS (
  SELECT
    i.customer_id,
    c.name as customer_name,
    i.balance,
    CASE
      WHEN i.due_date >= CURRENT_DATE THEN 'current'
      WHEN CURRENT_DATE - i.due_date BETWEEN 1 AND 30 THEN 'days1_30'
      WHEN CURRENT_DATE - i.due_date BETWEEN 31 AND 60 THEN 'days31_60'
      WHEN CURRENT_DATE - i.due_date BETWEEN 61 AND 90 THEN 'days61_90'
      ELSE 'days90_plus'
    END as bucket
  FROM invoices i
  JOIN customers c ON i.customer_id = c.id
  WHERE i.status IN ('SENT', 'PARTIAL', 'OVERDUE')
    AND i.balance > 0
)
SELECT
  customer_id,
  customer_name,
  SUM(CASE WHEN bucket = 'current' THEN balance ELSE 0 END) as current_amount,
  SUM(CASE WHEN bucket = 'days1_30' THEN balance ELSE 0 END) as days_1_30,
  SUM(CASE WHEN bucket = 'days31_60' THEN balance ELSE 0 END) as days_31_60,
  SUM(CASE WHEN bucket = 'days61_90' THEN balance ELSE 0 END) as days_61_90,
  SUM(CASE WHEN bucket = 'days90_plus' THEN balance ELSE 0 END) as days_90_plus,
  SUM(balance) as total
FROM invoice_aging
GROUP BY customer_id, customer_name
ORDER BY total DESC;
```

### Supplier Aging (Accounts Payable)

```sql
WITH bill_aging AS (
  SELECT
    b.supplier_id,
    s.name as supplier_name,
    b.balance,
    CASE
      WHEN b.due_date >= CURRENT_DATE THEN 'current'
      WHEN CURRENT_DATE - b.due_date BETWEEN 1 AND 30 THEN 'days1_30'
      WHEN CURRENT_DATE - b.due_date BETWEEN 31 AND 60 THEN 'days31_60'
      WHEN CURRENT_DATE - b.due_date BETWEEN 61 AND 90 THEN 'days61_90'
      ELSE 'days90_plus'
    END as bucket
  FROM purchase_bills b
  JOIN suppliers s ON b.supplier_id = s.id
  WHERE b.status IN ('PENDING', 'PARTIAL', 'OVERDUE')
    AND b.balance > 0
)
SELECT
  supplier_id,
  supplier_name,
  SUM(CASE WHEN bucket = 'current' THEN balance ELSE 0 END) as current_amount,
  SUM(CASE WHEN bucket = 'days1_30' THEN balance ELSE 0 END) as days_1_30,
  SUM(CASE WHEN bucket = 'days31_60' THEN balance ELSE 0 END) as days_31_60,
  SUM(CASE WHEN bucket = 'days61_90' THEN balance ELSE 0 END) as days_61_90,
  SUM(CASE WHEN bucket = 'days90_plus' THEN balance ELSE 0 END) as days_90_plus,
  SUM(balance) as total
FROM bill_aging
GROUP BY supplier_id, supplier_name
ORDER BY total DESC;
```

## Service Implementation

```typescript
// services/debtAging.ts

export const getReceivablesAging = async (): Promise<AgingReport> => {
  const invoices = await prisma.invoice.findMany({
    where: {
      status: { in: ['SENT', 'PARTIAL', 'OVERDUE'] },
      balance: { gt: 0 }
    },
    include: { customer: true }
  });

  const buckets = createEmptyBuckets();

  for (const invoice of invoices) {
    const daysOverdue = differenceInDays(new Date(), invoice.dueDate);
    const bucket = getBucket(daysOverdue);

    buckets[bucket].amount += Number(invoice.balance);
    buckets[bucket].count += 1;
  }

  const total = Object.values(buckets).reduce((sum, b) => sum + b.amount, 0);

  // Calculate percentages
  for (const bucket of Object.values(buckets)) {
    bucket.percentage = total > 0 ? (bucket.amount / total) * 100 : 0;
  }

  // Group by customer
  const byCustomer = groupByCustomer(invoices);

  return {
    type: 'receivable',
    asOfDate: new Date(),
    totalAmount: total,
    totalCount: invoices.length,
    buckets,
    byCustomer
  };
};

const getBucket = (daysOverdue: number): keyof AgingReport['buckets'] => {
  if (daysOverdue <= 0) return 'current';
  if (daysOverdue <= 30) return 'days1_30';
  if (daysOverdue <= 60) return 'days31_60';
  if (daysOverdue <= 90) return 'days61_90';
  return 'days90Plus';
};

const groupByCustomer = (invoices: Invoice[]): CustomerAging[] => {
  const grouped = new Map<string, CustomerAging>();

  for (const inv of invoices) {
    if (!grouped.has(inv.customerId)) {
      grouped.set(inv.customerId, {
        customerId: inv.customerId,
        customerName: inv.customer.name,
        current: 0,
        days1_30: 0,
        days31_60: 0,
        days61_90: 0,
        days90Plus: 0,
        total: 0
      });
    }

    const customer = grouped.get(inv.customerId)!;
    const bucket = getBucket(differenceInDays(new Date(), inv.dueDate));
    const balance = Number(inv.balance);

    switch (bucket) {
      case 'current': customer.current += balance; break;
      case 'days1_30': customer.days1_30 += balance; break;
      case 'days31_60': customer.days31_60 += balance; break;
      case 'days61_90': customer.days61_90 += balance; break;
      case 'days90Plus': customer.days90Plus += balance; break;
    }
    customer.total += balance;
  }

  return Array.from(grouped.values()).sort((a, b) => b.total - a.total);
};
```

## Components

### AgingSummaryChart

```tsx
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';

const AgingSummaryChart = ({ report }: { report: AgingReport }) => {
  const data = [
    { name: 'Current', amount: report.buckets.current.amount, color: '#22c55e' },
    { name: '1-30', amount: report.buckets.days1_30.amount, color: '#eab308' },
    { name: '31-60', amount: report.buckets.days31_60.amount, color: '#f97316' },
    { name: '61-90', amount: report.buckets.days61_90.amount, color: '#ef4444' },
    { name: '90+', amount: report.buckets.days90Plus.amount, color: '#7f1d1d' }
  ];

  return (
    <ResponsiveContainer width="100%" height={300}>
      <BarChart data={data}>
        <XAxis dataKey="name" />
        <YAxis tickFormatter={(v) => formatCurrencyShort(v)} />
        <Tooltip
          formatter={(value) => formatCurrency(value as number)}
          labelFormatter={(label) => `${label} days overdue`}
        />
        <Bar dataKey="amount">
          {data.map((entry, index) => (
            <Cell key={index} fill={entry.color} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
};
```

### AgingTable

```tsx
const AgingTable = ({ data, type }: { data: CustomerAging[] | SupplierAging[], type: 'customer' | 'supplier' }) => (
  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>{type === 'customer' ? 'Customer' : 'Supplier'}</TableHead>
        <TableHead className="text-right">Current</TableHead>
        <TableHead className="text-right">1-30 Days</TableHead>
        <TableHead className="text-right">31-60 Days</TableHead>
        <TableHead className="text-right">61-90 Days</TableHead>
        <TableHead className="text-right">90+ Days</TableHead>
        <TableHead className="text-right font-bold">Total</TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      {data.map((row) => (
        <TableRow key={row.customerId || row.supplierId}>
          <TableCell className="font-medium">
            {row.customerName || row.supplierName}
          </TableCell>
          <TableCell className="text-right">
            {formatCurrency(row.current)}
          </TableCell>
          <TableCell className="text-right text-yellow-600">
            {formatCurrency(row.days1_30)}
          </TableCell>
          <TableCell className="text-right text-orange-600">
            {formatCurrency(row.days31_60)}
          </TableCell>
          <TableCell className="text-right text-red-600">
            {formatCurrency(row.days61_90)}
          </TableCell>
          <TableCell className="text-right text-red-800 font-medium">
            {formatCurrency(row.days90Plus)}
          </TableCell>
          <TableCell className="text-right font-bold">
            {formatCurrency(row.total)}
          </TableCell>
        </TableRow>
      ))}
    </TableBody>
    <TableFooter>
      <TableRow>
        <TableCell className="font-bold">Total</TableCell>
        <TableCell className="text-right font-bold">
          {formatCurrency(data.reduce((s, r) => s + r.current, 0))}
        </TableCell>
        <TableCell className="text-right font-bold">
          {formatCurrency(data.reduce((s, r) => s + r.days1_30, 0))}
        </TableCell>
        <TableCell className="text-right font-bold">
          {formatCurrency(data.reduce((s, r) => s + r.days31_60, 0))}
        </TableCell>
        <TableCell className="text-right font-bold">
          {formatCurrency(data.reduce((s, r) => s + r.days61_90, 0))}
        </TableCell>
        <TableCell className="text-right font-bold">
          {formatCurrency(data.reduce((s, r) => s + r.days90Plus, 0))}
        </TableCell>
        <TableCell className="text-right font-bold">
          {formatCurrency(data.reduce((s, r) => s + r.total, 0))}
        </TableCell>
      </TableRow>
    </TableFooter>
  </Table>
);
```

### AgingTrendChart

```tsx
const AgingTrendChart = ({ history }: { history: AgingSnapshot[] }) => {
  // history = monthly snapshots of aging
  return (
    <ResponsiveContainer width="100%" height={300}>
      <AreaChart data={history}>
        <XAxis dataKey="month" />
        <YAxis tickFormatter={(v) => formatCurrencyShort(v)} />
        <Tooltip />
        <Legend />
        <Area
          type="monotone"
          dataKey="current"
          stackId="1"
          stroke="#22c55e"
          fill="#22c55e"
          name="Current"
        />
        <Area
          type="monotone"
          dataKey="days1_30"
          stackId="1"
          stroke="#eab308"
          fill="#eab308"
          name="1-30 Days"
        />
        <Area
          type="monotone"
          dataKey="days31_60"
          stackId="1"
          stroke="#f97316"
          fill="#f97316"
          name="31-60 Days"
        />
        <Area
          type="monotone"
          dataKey="days61_90"
          stackId="1"
          stroke="#ef4444"
          fill="#ef4444"
          name="61-90 Days"
        />
        <Area
          type="monotone"
          dataKey="days90Plus"
          stackId="1"
          stroke="#7f1d1d"
          fill="#7f1d1d"
          name="90+ Days"
        />
      </AreaChart>
    </ResponsiveContainer>
  );
};
```

## Bad Debt Analysis

```typescript
interface BadDebtAnalysis {
  totalBadDebt: number;
  writeOffCandidates: WriteOffCandidate[];
  provision: number;          // Suggested provision amount
}

interface WriteOffCandidate {
  invoiceId: string;
  invoiceNumber: string;
  customerId: string;
  customerName: string;
  amount: number;
  daysOverdue: number;
  lastContactDate?: Date;
  collectionAttempts: number;
  recommendation: 'write_off' | 'collections' | 'legal';
}

export const analyzeBadDebt = async (): Promise<BadDebtAnalysis> => {
  const overdueInvoices = await prisma.invoice.findMany({
    where: {
      status: 'OVERDUE',
      balance: { gt: 0 },
      dueDate: { lt: subDays(new Date(), 90) }
    },
    include: {
      customer: true,
      collectionHistory: true
    }
  });

  const candidates: WriteOffCandidate[] = overdueInvoices.map(inv => {
    const daysOverdue = differenceInDays(new Date(), inv.dueDate);
    const attempts = inv.collectionHistory.length;

    let recommendation: WriteOffCandidate['recommendation'];
    if (daysOverdue > 180 && attempts >= 5) {
      recommendation = 'write_off';
    } else if (daysOverdue > 120) {
      recommendation = 'legal';
    } else {
      recommendation = 'collections';
    }

    return {
      invoiceId: inv.id,
      invoiceNumber: inv.invoiceNumber,
      customerId: inv.customerId,
      customerName: inv.customer.name,
      amount: Number(inv.balance),
      daysOverdue,
      lastContactDate: inv.collectionHistory[0]?.createdAt,
      collectionAttempts: attempts,
      recommendation
    };
  });

  // Calculate provision based on aging
  const provision = calculateProvision(overdueInvoices);

  return {
    totalBadDebt: candidates.reduce((sum, c) => sum + c.amount, 0),
    writeOffCandidates: candidates,
    provision
  };
};

const calculateProvision = (invoices: Invoice[]): number => {
  // Provision rates by aging bucket
  const rates = {
    current: 0.01,     // 1%
    days1_30: 0.02,    // 2%
    days31_60: 0.05,   // 5%
    days61_90: 0.10,   // 10%
    days90_180: 0.25,  // 25%
    days180Plus: 0.50  // 50%
  };

  return invoices.reduce((sum, inv) => {
    const days = differenceInDays(new Date(), inv.dueDate);
    let rate = rates.current;

    if (days > 180) rate = rates.days180Plus;
    else if (days > 90) rate = rates.days90_180;
    else if (days > 60) rate = rates.days61_90;
    else if (days > 30) rate = rates.days31_60;
    else if (days > 0) rate = rates.days1_30;

    return sum + Number(inv.balance) * rate;
  }, 0);
};
```
