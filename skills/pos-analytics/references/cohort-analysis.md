# Cohort Analysis

Phân tích behavior của customer groups theo thời gian.

## Overview

Cohort analysis nhóm khách hàng theo thời điểm (tháng đăng ký) và theo dõi hành vi của họ qua thời gian để hiểu retention và lifetime value.

## Cohort Types

### 1. Acquisition Cohort
Nhóm theo tháng first purchase

### 2. Behavioral Cohort
Nhóm theo hành vi (VIP, regular, etc.)

### 3. Size Cohort
Nhóm theo giá trị đơn hàng

## Data Model

```typescript
interface Cohort {
  cohortId: string;           // e.g., "2024-01"
  cohortMonth: Date;
  totalCustomers: number;
  periods: CohortPeriod[];
}

interface CohortPeriod {
  period: number;             // Months since cohort
  activeCustomers: number;
  revenue: number;
  orders: number;
  retentionRate: number;
}

interface CohortMatrix {
  cohorts: string[];          // Row labels
  periods: number[];          // Column labels
  values: number[][];         // Retention rates
}
```

## SQL Queries

### Generate Cohort Data

```sql
WITH customer_cohorts AS (
  -- Assign each customer to their first purchase month
  SELECT
    customer_id,
    DATE_TRUNC('month', MIN(created_at)) as cohort_month
  FROM orders
  WHERE status = 'completed'
  GROUP BY customer_id
),
customer_activity AS (
  -- Get monthly activity for each customer
  SELECT
    o.customer_id,
    c.cohort_month,
    DATE_TRUNC('month', o.created_at) as activity_month,
    COUNT(*) as orders,
    SUM(o.total_amount) as revenue
  FROM orders o
  JOIN customer_cohorts c ON o.customer_id = c.customer_id
  WHERE o.status = 'completed'
  GROUP BY o.customer_id, c.cohort_month, DATE_TRUNC('month', o.created_at)
)
SELECT
  cohort_month,
  EXTRACT(MONTH FROM age(activity_month, cohort_month)) as period,
  COUNT(DISTINCT customer_id) as customers,
  SUM(orders) as orders,
  SUM(revenue) as revenue
FROM customer_activity
GROUP BY cohort_month, period
ORDER BY cohort_month, period;
```

### Retention Rate by Cohort

```sql
WITH cohort_sizes AS (
  SELECT
    DATE_TRUNC('month', MIN(created_at)) as cohort_month,
    COUNT(DISTINCT customer_id) as cohort_size
  FROM orders
  WHERE status = 'completed'
  GROUP BY customer_id
),
cohort_retention AS (
  SELECT
    c.cohort_month,
    EXTRACT(MONTH FROM age(DATE_TRUNC('month', o.created_at), c.cohort_month)) as period,
    COUNT(DISTINCT o.customer_id) as retained_customers
  FROM orders o
  JOIN (
    SELECT customer_id, DATE_TRUNC('month', MIN(created_at)) as cohort_month
    FROM orders WHERE status = 'completed'
    GROUP BY customer_id
  ) c ON o.customer_id = c.customer_id
  WHERE o.status = 'completed'
  GROUP BY c.cohort_month, period
)
SELECT
  cr.cohort_month,
  cr.period,
  cr.retained_customers,
  cs.cohort_size,
  ROUND(cr.retained_customers::decimal / cs.cohort_size * 100, 2) as retention_rate
FROM cohort_retention cr
JOIN (
  SELECT cohort_month, SUM(cohort_size) as cohort_size
  FROM cohort_sizes
  GROUP BY cohort_month
) cs ON cr.cohort_month = cs.cohort_month
ORDER BY cr.cohort_month, cr.period;
```

## Implementation

### Cohort Service

```typescript
// services/cohortAnalysis.ts
export const generateCohortMatrix = async (
  startDate: Date,
  endDate: Date
): Promise<CohortMatrix> => {
  const data = await prisma.$queryRaw<CohortData[]>`
    -- cohort query above
  `;

  // Transform to matrix format
  const cohorts = [...new Set(data.map(d => d.cohort_month))];
  const maxPeriod = Math.max(...data.map(d => d.period));
  const periods = Array.from({ length: maxPeriod + 1 }, (_, i) => i);

  const values = cohorts.map(cohort => {
    return periods.map(period => {
      const cell = data.find(
        d => d.cohort_month === cohort && d.period === period
      );
      return cell?.retention_rate ?? null;
    });
  });

  return { cohorts, periods, values };
};
```

### Calculate LTV by Cohort

```typescript
export const calculateCohortLTV = async (cohortMonth: string): Promise<number> => {
  const result = await prisma.$queryRaw`
    WITH cohort_customers AS (
      SELECT DISTINCT customer_id
      FROM orders
      WHERE status = 'completed'
      GROUP BY customer_id
      HAVING DATE_TRUNC('month', MIN(created_at)) = ${cohortMonth}::date
    )
    SELECT
      AVG(customer_total) as average_ltv
    FROM (
      SELECT
        customer_id,
        SUM(total_amount) as customer_total
      FROM orders
      WHERE customer_id IN (SELECT customer_id FROM cohort_customers)
        AND status = 'completed'
      GROUP BY customer_id
    ) customer_totals
  `;

  return result[0]?.average_ltv ?? 0;
};
```

## Components

### CohortTable

```tsx
interface CohortTableProps {
  matrix: CohortMatrix;
}

const CohortTable = ({ matrix }: CohortTableProps) => {
  const getColor = (value: number | null) => {
    if (value === null) return 'bg-gray-100';
    if (value >= 50) return 'bg-green-500 text-white';
    if (value >= 30) return 'bg-green-300';
    if (value >= 20) return 'bg-yellow-300';
    if (value >= 10) return 'bg-orange-300';
    return 'bg-red-300';
  };

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full">
        <thead>
          <tr>
            <th className="px-4 py-2">Cohort</th>
            {matrix.periods.map(p => (
              <th key={p} className="px-4 py-2 text-center">
                Month {p}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {matrix.cohorts.map((cohort, i) => (
            <tr key={cohort}>
              <td className="px-4 py-2 font-medium">
                {formatMonth(cohort)}
              </td>
              {matrix.values[i].map((value, j) => (
                <td
                  key={j}
                  className={cn(
                    "px-4 py-2 text-center",
                    getColor(value)
                  )}
                >
                  {value !== null ? `${value.toFixed(1)}%` : '-'}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
```

### CohortChart

```tsx
import { LineChart, Line, XAxis, YAxis, Tooltip, Legend, ResponsiveContainer } from 'recharts';

const CohortChart = ({ matrix }: { matrix: CohortMatrix }) => {
  // Transform for line chart - each cohort is a line
  const data = matrix.periods.map(period => {
    const point: Record<string, number> = { period };
    matrix.cohorts.forEach((cohort, i) => {
      point[cohort] = matrix.values[i][period] ?? 0;
    });
    return point;
  });

  const colors = ['#8884d8', '#82ca9d', '#ffc658', '#ff7c43', '#a4de6c'];

  return (
    <ResponsiveContainer width="100%" height={400}>
      <LineChart data={data}>
        <XAxis dataKey="period" label={{ value: 'Month', position: 'bottom' }} />
        <YAxis label={{ value: 'Retention %', angle: -90, position: 'left' }} />
        <Tooltip />
        <Legend />
        {matrix.cohorts.slice(0, 5).map((cohort, i) => (
          <Line
            key={cohort}
            type="monotone"
            dataKey={cohort}
            stroke={colors[i % colors.length]}
            name={formatMonth(cohort)}
          />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
};
```

## Churn Prediction

```typescript
interface ChurnPrediction {
  customerId: string;
  churnProbability: number;
  riskLevel: 'low' | 'medium' | 'high';
  lastPurchase: Date;
  daysSinceLastPurchase: number;
}

const predictChurn = async (): Promise<ChurnPrediction[]> => {
  // Get customer activity metrics
  const customers = await prisma.$queryRaw`
    SELECT
      customer_id,
      MAX(created_at) as last_purchase,
      COUNT(*) as order_count,
      AVG(EXTRACT(EPOCH FROM (
        LEAD(created_at) OVER (PARTITION BY customer_id ORDER BY created_at) - created_at
      )) / 86400) as avg_days_between_orders
    FROM orders
    WHERE status = 'completed'
    GROUP BY customer_id
  `;

  return customers.map(c => {
    const daysSince = differenceInDays(new Date(), c.last_purchase);
    const expectedInterval = c.avg_days_between_orders || 30;

    // Simple probability based on deviation from expected interval
    const deviation = daysSince / expectedInterval;
    const churnProbability = Math.min(1, deviation / 3);

    return {
      customerId: c.customer_id,
      churnProbability,
      riskLevel:
        churnProbability >= 0.7 ? 'high' :
        churnProbability >= 0.4 ? 'medium' : 'low',
      lastPurchase: c.last_purchase,
      daysSinceLastPurchase: daysSince
    };
  });
};
```
