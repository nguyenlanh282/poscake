# Return Analytics

Phân tích dữ liệu đổi trả để cải thiện sản phẩm và quy trình.

## Overview

Return analytics giúp hiểu patterns trong đổi trả, identify problem products, và optimize return policies.

## Key Metrics

```typescript
interface ReturnMetrics {
  // Volume metrics
  totalReturns: number;
  totalItems: number;
  returnRate: number;           // Returns / Orders %
  itemReturnRate: number;       // Returned items / Sold items %

  // Financial metrics
  returnValue: number;          // Total value of returns
  refundAmount: number;         // Total refunded
  restockingFeeCollected: number;
  netReturnCost: number;

  // Processing metrics
  avgProcessingDays: number;
  autoApprovalRate: number;
  inspectionPassRate: number;
  restockRate: number;          // % restocked vs disposed

  // Trend
  periodComparison: {
    previous: number;
    current: number;
    change: number;
  };
}

interface ReturnsByReason {
  reason: ReturnReason;
  count: number;
  percentage: number;
  value: number;
  trend: 'up' | 'down' | 'stable';
}

interface ReturnsByProduct {
  productId: string;
  productName: string;
  returnCount: number;
  salesCount: number;
  returnRate: number;
  topReason: ReturnReason;
  totalValue: number;
}

interface ReturnsByCategory {
  categoryId: string;
  categoryName: string;
  returnCount: number;
  returnRate: number;
  avgProcessingDays: number;
}
```

## SQL Queries

### Return Rate by Product

```sql
WITH product_sales AS (
  SELECT
    oi.product_id,
    p.name as product_name,
    c.name as category_name,
    COUNT(DISTINCT oi.id) as units_sold,
    SUM(oi.quantity * oi.unit_price) as sales_value
  FROM order_items oi
  JOIN products p ON oi.product_id = p.id
  JOIN categories c ON p.category_id = c.id
  JOIN orders o ON oi.order_id = o.id
  WHERE o.status = 'completed'
    AND o.created_at >= NOW() - INTERVAL '90 days'
  GROUP BY oi.product_id, p.name, c.name
),
product_returns AS (
  SELECT
    ri.product_id,
    COUNT(DISTINCT ri.id) as units_returned,
    SUM(ri.quantity * ri.unit_price) as return_value,
    MODE() WITHIN GROUP (ORDER BY ri.reason) as top_reason
  FROM rma_items ri
  JOIN rmas r ON ri.rma_id = r.id
  WHERE r.status = 'completed'
    AND r.completed_at >= NOW() - INTERVAL '90 days'
  GROUP BY ri.product_id
)
SELECT
  ps.product_id,
  ps.product_name,
  ps.category_name,
  ps.units_sold,
  COALESCE(pr.units_returned, 0) as units_returned,
  ROUND(COALESCE(pr.units_returned, 0)::decimal / ps.units_sold * 100, 2) as return_rate,
  pr.top_reason,
  COALESCE(pr.return_value, 0) as return_value
FROM product_sales ps
LEFT JOIN product_returns pr ON ps.product_id = pr.product_id
ORDER BY return_rate DESC
LIMIT 50;
```

### Returns by Reason Over Time

```sql
SELECT
  DATE_TRUNC('week', r.completed_at) as week,
  ri.reason,
  COUNT(*) as count,
  SUM(ri.quantity * ri.unit_price) as value
FROM rma_items ri
JOIN rmas r ON ri.rma_id = r.id
WHERE r.status = 'completed'
  AND r.completed_at >= NOW() - INTERVAL '12 weeks'
GROUP BY week, ri.reason
ORDER BY week, count DESC;
```

### Return Cost Analysis

```sql
SELECT
  DATE_TRUNC('month', r.completed_at) as month,
  COUNT(DISTINCT r.id) as return_count,
  SUM(ref.items_amount) as items_value,
  SUM(ref.shipping_amount) as shipping_refunded,
  SUM(ref.restocking_fee) as restocking_collected,
  SUM(ref.total_amount) as total_refunded,
  SUM(ia.write_off_amount) as inventory_written_off,
  -- Net cost = refunded + written off - restocking fees
  SUM(ref.total_amount) + COALESCE(SUM(ia.write_off_amount), 0) - SUM(ref.restocking_fee) as net_cost
FROM rmas r
JOIN refunds ref ON r.id = ref.rma_id
LEFT JOIN inventory_adjustments ia ON r.id = ia.rma_id
WHERE r.status = 'completed'
  AND r.completed_at >= NOW() - INTERVAL '12 months'
GROUP BY month
ORDER BY month;
```

## Service Implementation

```typescript
// services/returnAnalytics.ts

export const getReturnDashboard = async (
  dateRange: DateRange
): Promise<ReturnDashboard> => {
  const [metrics, byReason, byProduct, byCategory, trends] = await Promise.all([
    getReturnMetrics(dateRange),
    getReturnsByReason(dateRange),
    getTopReturnedProducts(dateRange, 20),
    getReturnsByCategory(dateRange),
    getReturnTrends(dateRange)
  ]);

  return {
    metrics,
    byReason,
    byProduct,
    byCategory,
    trends
  };
};

export const getReturnMetrics = async (dateRange: DateRange): Promise<ReturnMetrics> => {
  const result = await prisma.$queryRaw`
    WITH period_returns AS (
      SELECT
        COUNT(DISTINCT r.id) as total_returns,
        SUM(ri.quantity) as total_items,
        SUM(ref.total_amount) as refund_amount,
        SUM(ref.restocking_fee) as restocking_fee,
        AVG(EXTRACT(DAY FROM r.completed_at - r.requested_at)) as avg_days
      FROM rmas r
      JOIN rma_items ri ON r.id = ri.rma_id
      LEFT JOIN refunds ref ON r.id = ref.rma_id
      WHERE r.status = 'completed'
        AND r.completed_at BETWEEN ${dateRange.start} AND ${dateRange.end}
    ),
    period_orders AS (
      SELECT COUNT(*) as order_count, SUM(total_amount) as order_value
      FROM orders
      WHERE status = 'completed'
        AND created_at BETWEEN ${dateRange.start} AND ${dateRange.end}
    )
    SELECT
      pr.*,
      po.order_count,
      (pr.total_returns::decimal / po.order_count * 100) as return_rate
    FROM period_returns pr, period_orders po
  `;

  return result[0];
};

export const getTopReturnedProducts = async (
  dateRange: DateRange,
  limit: number
): Promise<ReturnsByProduct[]> => {
  return await prisma.$queryRaw`
    WITH sales AS (
      SELECT product_id, COUNT(*) as sales_count
      FROM order_items oi
      JOIN orders o ON oi.order_id = o.id
      WHERE o.created_at BETWEEN ${dateRange.start} AND ${dateRange.end}
      GROUP BY product_id
    ),
    returns AS (
      SELECT
        ri.product_id,
        COUNT(*) as return_count,
        SUM(ri.quantity * ri.unit_price) as return_value,
        MODE() WITHIN GROUP (ORDER BY ri.reason) as top_reason
      FROM rma_items ri
      JOIN rmas r ON ri.rma_id = r.id
      WHERE r.completed_at BETWEEN ${dateRange.start} AND ${dateRange.end}
      GROUP BY ri.product_id
    )
    SELECT
      r.product_id,
      p.name as product_name,
      r.return_count,
      s.sales_count,
      ROUND(r.return_count::decimal / s.sales_count * 100, 2) as return_rate,
      r.top_reason,
      r.return_value
    FROM returns r
    JOIN sales s ON r.product_id = s.product_id
    JOIN products p ON r.product_id = p.id
    ORDER BY return_rate DESC
    LIMIT ${limit}
  `;
};

export const getReturnTrends = async (dateRange: DateRange) => {
  return await prisma.$queryRaw`
    SELECT
      DATE_TRUNC('day', completed_at) as date,
      COUNT(*) as returns,
      SUM(
        SELECT SUM(quantity * unit_price) FROM rma_items WHERE rma_id = rmas.id
      ) as value
    FROM rmas
    WHERE status = 'completed'
      AND completed_at BETWEEN ${dateRange.start} AND ${dateRange.end}
    GROUP BY date
    ORDER BY date
  `;
};
```

## Problem Product Detection

```typescript
interface ProblemProduct {
  productId: string;
  productName: string;
  alertType: 'high_return_rate' | 'defect_pattern' | 'size_issues' | 'description_mismatch';
  severity: 'low' | 'medium' | 'high' | 'critical';
  returnRate: number;
  returnCount: number;
  primaryReason: ReturnReason;
  recommendation: string;
  samples: RMAItem[];
}

export const detectProblemProducts = async (): Promise<ProblemProduct[]> => {
  const problems: ProblemProduct[] = [];

  // High return rate products
  const highReturnRate = await prisma.$queryRaw`
    SELECT * FROM get_product_return_rates()
    WHERE return_rate > 10
      AND sales_count >= 20
    ORDER BY return_rate DESC
  `;

  for (const product of highReturnRate) {
    const severity = product.return_rate > 25 ? 'critical'
      : product.return_rate > 15 ? 'high'
      : 'medium';

    problems.push({
      productId: product.product_id,
      productName: product.product_name,
      alertType: 'high_return_rate',
      severity,
      returnRate: product.return_rate,
      returnCount: product.return_count,
      primaryReason: product.top_reason,
      recommendation: getRecommendation(product.top_reason, product.return_rate),
      samples: await getRecentReturns(product.product_id, 5)
    });
  }

  // Defect patterns (same reason recurring)
  const defectPatterns = await prisma.$queryRaw`
    SELECT
      product_id,
      reason,
      COUNT(*) as count,
      ARRAY_AGG(DISTINCT ri.id ORDER BY r.created_at DESC) as sample_ids
    FROM rma_items ri
    JOIN rmas r ON ri.rma_id = r.id
    WHERE ri.reason = 'defective'
      AND r.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY product_id, reason
    HAVING COUNT(*) >= 3
  `;

  for (const pattern of defectPatterns) {
    problems.push({
      productId: pattern.product_id,
      productName: await getProductName(pattern.product_id),
      alertType: 'defect_pattern',
      severity: pattern.count >= 10 ? 'critical' : 'high',
      returnRate: 0,
      returnCount: pattern.count,
      primaryReason: 'defective',
      recommendation: 'Review product quality with supplier. Consider pulling from sale.',
      samples: pattern.sample_ids
    });
  }

  return problems;
};

const getRecommendation = (reason: ReturnReason, rate: number): string => {
  const recommendations: Record<ReturnReason, string> = {
    defective: 'Review supplier quality. Consider product recall if rate > 20%.',
    wrong_item: 'Audit fulfillment process. Check picking accuracy.',
    not_as_described: 'Update product photos and description. Review customer feedback.',
    size_issue: 'Add size guide. Consider updating size chart based on returns.',
    changed_mind: 'Normal customer behavior. Ensure policy is clear.',
    damaged_shipping: 'Review packaging. Consider upgraded shipping materials.',
    quality_issue: 'Review product quality standards. Get customer feedback.',
    other: 'Review individual cases for patterns.'
  };

  return recommendations[reason] || 'Review return details for insights.';
};
```

## Components

### ReturnsDashboard

```tsx
const ReturnsDashboard = () => {
  const [dateRange, setDateRange] = useState<DateRange>(last30Days());

  const { data: dashboard } = useQuery({
    queryKey: ['returns-dashboard', dateRange],
    queryFn: () => fetch(`/api/returns/analytics?${toQueryString(dateRange)}`).then(r => r.json())
  });

  return (
    <div className="space-y-6">
      {/* Metrics cards */}
      <div className="grid grid-cols-4 gap-4">
        <MetricCard
          title="Return Rate"
          value={`${dashboard?.metrics.returnRate.toFixed(1)}%`}
          trend={dashboard?.metrics.periodComparison}
          trendDirection="down-is-good"
        />
        <MetricCard
          title="Total Returns"
          value={dashboard?.metrics.totalReturns}
        />
        <MetricCard
          title="Refund Amount"
          value={formatCurrency(dashboard?.metrics.refundAmount)}
        />
        <MetricCard
          title="Avg Processing Days"
          value={`${dashboard?.metrics.avgProcessingDays.toFixed(1)} days`}
        />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle>Returns by Reason</CardTitle>
          </CardHeader>
          <CardContent>
            <ReasonsPieChart data={dashboard?.byReason} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Return Trend</CardTitle>
          </CardHeader>
          <CardContent>
            <ReturnTrendChart data={dashboard?.trends} />
          </CardContent>
        </Card>
      </div>

      {/* Problem products */}
      <Card>
        <CardHeader>
          <CardTitle>Problem Products</CardTitle>
          <CardDescription>Products with unusually high return rates</CardDescription>
        </CardHeader>
        <CardContent>
          <ProblemProductsTable data={dashboard?.byProduct.filter(p => p.returnRate > 10)} />
        </CardContent>
      </Card>

      {/* Category breakdown */}
      <Card>
        <CardHeader>
          <CardTitle>Returns by Category</CardTitle>
        </CardHeader>
        <CardContent>
          <CategoryReturnsChart data={dashboard?.byCategory} />
        </CardContent>
      </Card>
    </div>
  );
};
```

### ReasonsPieChart

```tsx
import { PieChart, Pie, Cell, Legend, Tooltip, ResponsiveContainer } from 'recharts';

const ReasonsPieChart = ({ data }: { data: ReturnsByReason[] }) => {
  const colors = {
    defective: '#ef4444',
    wrong_item: '#f97316',
    not_as_described: '#eab308',
    size_issue: '#22c55e',
    changed_mind: '#3b82f6',
    damaged_shipping: '#8b5cf6',
    quality_issue: '#ec4899',
    other: '#6b7280'
  };

  return (
    <ResponsiveContainer width="100%" height={300}>
      <PieChart>
        <Pie
          data={data}
          dataKey="count"
          nameKey="reason"
          cx="50%"
          cy="50%"
          outerRadius={100}
          label={({ reason, percentage }) => `${getReasonLabel(reason)} (${percentage.toFixed(0)}%)`}
        >
          {data.map((entry, index) => (
            <Cell key={entry.reason} fill={colors[entry.reason]} />
          ))}
        </Pie>
        <Tooltip
          formatter={(value, name) => [value, getReasonLabel(name as string)]}
        />
        <Legend formatter={(value) => getReasonLabel(value)} />
      </PieChart>
    </ResponsiveContainer>
  );
};
```
