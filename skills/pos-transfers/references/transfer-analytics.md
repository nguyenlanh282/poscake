# Transfer Analytics

Phân tích dữ liệu chuyển kho để tối ưu hóa logistics.

## Overview

Transfer analytics cung cấp insights về patterns, performance, và costs của transfers để optimize inventory distribution.

## Key Metrics

```typescript
interface TransferMetrics {
  // Volume
  totalTransfers: number;
  totalItems: number;
  totalValue: number;

  // Performance
  avgLeadTimeDays: number;
  onTimeRate: number;           // % delivered on time
  accuracyRate: number;         // % without discrepancies

  // Cost
  totalShippingCost: number;
  avgCostPerTransfer: number;
  avgCostPerItem: number;

  // Efficiency
  approvalCycleHours: number;
  pickingTimeMinutes: number;
  turnaroundDays: number;       // Request to complete

  // Trends
  volumeTrend: TrendDirection;
  costTrend: TrendDirection;
}

interface RouteAnalytics {
  sourceWarehouseId: string;
  sourceName: string;
  destinationWarehouseId: string;
  destinationName: string;

  // Stats
  transferCount: number;
  totalQuantity: number;
  totalValue: number;

  // Performance
  avgLeadTime: number;
  onTimeRate: number;
  discrepancyRate: number;

  // Cost
  avgShippingCost: number;
  costPerUnit: number;
}

interface ProductTransferAnalytics {
  productId: string;
  productName: string;
  sku: string;

  // Movement
  transferCount: number;
  totalQuantity: number;
  avgTransferQty: number;

  // Distribution
  warehouseDistribution: {
    warehouseId: string;
    warehouseName: string;
    currentStock: number;
    avgStock: number;
    turnover: number;
  }[];

  // Issues
  discrepancyCount: number;
  discrepancyRate: number;
}
```

## SQL Queries

### Transfer Volume by Route

```sql
SELECT
  t.source_warehouse_id,
  sw.name as source_name,
  t.destination_warehouse_id,
  dw.name as dest_name,
  COUNT(*) as transfer_count,
  SUM(t.total_quantity) as total_quantity,
  SUM(t.total_cost) as total_value,
  AVG(EXTRACT(DAY FROM t.received_at - t.shipped_at)) as avg_lead_time,
  SUM(CASE WHEN t.received_at <= t.expected_arrival THEN 1 ELSE 0 END)::decimal
    / COUNT(*) * 100 as on_time_rate
FROM transfer_requests t
JOIN warehouses sw ON t.source_warehouse_id = sw.id
JOIN warehouses dw ON t.destination_warehouse_id = dw.id
WHERE t.status = 'completed'
  AND t.completed_at >= NOW() - INTERVAL '90 days'
GROUP BY t.source_warehouse_id, sw.name, t.destination_warehouse_id, dw.name
ORDER BY transfer_count DESC;
```

### Lead Time Analysis

```sql
SELECT
  DATE_TRUNC('week', completed_at) as week,
  AVG(EXTRACT(DAY FROM received_at - requested_at)) as request_to_receive,
  AVG(EXTRACT(DAY FROM approved_at - requested_at)) as approval_time,
  AVG(EXTRACT(DAY FROM shipped_at - approved_at)) as picking_time,
  AVG(EXTRACT(DAY FROM received_at - shipped_at)) as transit_time,
  COUNT(*) as transfers
FROM transfer_requests
WHERE status = 'completed'
  AND completed_at >= NOW() - INTERVAL '12 weeks'
GROUP BY week
ORDER BY week;
```

### Discrepancy Analysis

```sql
SELECT
  d.reason,
  COUNT(*) as occurrence_count,
  SUM(ABS(d.variance)) as total_variance_qty,
  SUM(ABS(d.variance) * ti.unit_cost) as total_variance_value,
  AVG(ABS(d.variance_percent)) as avg_variance_percent
FROM transfer_discrepancies d
JOIN transfer_items ti ON d.transfer_item_id = ti.id
WHERE d.created_at >= NOW() - INTERVAL '90 days'
GROUP BY d.reason
ORDER BY occurrence_count DESC;
```

## Service Implementation

```typescript
// services/transferAnalytics.ts

export const getTransferDashboard = async (
  dateRange: DateRange
): Promise<TransferDashboard> => {
  const [metrics, byRoute, byProduct, trends, discrepancies] = await Promise.all([
    getTransferMetrics(dateRange),
    getRouteAnalytics(dateRange),
    getProductAnalytics(dateRange),
    getTransferTrends(dateRange),
    getDiscrepancyAnalysis(dateRange)
  ]);

  return {
    metrics,
    byRoute,
    byProduct,
    trends,
    discrepancies
  };
};

export const getTransferMetrics = async (
  dateRange: DateRange
): Promise<TransferMetrics> => {
  const result = await prisma.$queryRaw`
    WITH transfer_stats AS (
      SELECT
        COUNT(*) as total_transfers,
        SUM(total_quantity) as total_items,
        SUM(total_cost) as total_value,
        AVG(EXTRACT(DAY FROM received_at - shipped_at)) as avg_lead_time,
        SUM(CASE WHEN received_at <= expected_arrival THEN 1 ELSE 0 END)::decimal / COUNT(*) as on_time_rate,
        AVG(EXTRACT(HOUR FROM approved_at - requested_at)) as approval_cycle,
        AVG(EXTRACT(DAY FROM completed_at - requested_at)) as turnaround
      FROM transfer_requests
      WHERE status = 'completed'
        AND completed_at BETWEEN ${dateRange.start} AND ${dateRange.end}
    ),
    discrepancy_stats AS (
      SELECT
        COUNT(DISTINCT t.id) as transfers_with_issues,
        COUNT(t.id) as total_completed
      FROM transfer_requests t
      LEFT JOIN transfer_discrepancies d ON t.id = d.transfer_id
      WHERE t.status = 'completed'
        AND t.completed_at BETWEEN ${dateRange.start} AND ${dateRange.end}
    ),
    cost_stats AS (
      SELECT
        SUM(s.total_cost) as shipping_cost
      FROM shipments s
      JOIN transfer_requests t ON s.transfer_id = t.id
      WHERE t.completed_at BETWEEN ${dateRange.start} AND ${dateRange.end}
    )
    SELECT
      ts.*,
      (ds.total_completed - ds.transfers_with_issues)::decimal / ds.total_completed as accuracy_rate,
      cs.shipping_cost as total_shipping_cost
    FROM transfer_stats ts, discrepancy_stats ds, cost_stats cs
  `;

  return result[0];
};

export const getRouteAnalytics = async (
  dateRange: DateRange
): Promise<RouteAnalytics[]> => {
  return await prisma.$queryRaw`
    SELECT
      t.source_warehouse_id,
      sw.name as source_name,
      t.destination_warehouse_id,
      dw.name as destination_name,
      COUNT(*) as transfer_count,
      SUM(t.total_quantity) as total_quantity,
      SUM(t.total_cost) as total_value,
      AVG(EXTRACT(DAY FROM t.received_at - t.shipped_at)) as avg_lead_time,
      SUM(CASE WHEN t.received_at <= t.expected_arrival THEN 1 ELSE 0 END)::decimal
        / NULLIF(COUNT(*), 0) * 100 as on_time_rate,
      COUNT(d.id)::decimal / NULLIF(COUNT(*), 0) * 100 as discrepancy_rate,
      AVG(s.shipping_cost) as avg_shipping_cost,
      SUM(s.shipping_cost) / NULLIF(SUM(t.total_quantity), 0) as cost_per_unit
    FROM transfer_requests t
    JOIN warehouses sw ON t.source_warehouse_id = sw.id
    JOIN warehouses dw ON t.destination_warehouse_id = dw.id
    LEFT JOIN transfer_discrepancies d ON t.id = d.transfer_id
    LEFT JOIN shipments s ON t.id = s.transfer_id
    WHERE t.status = 'completed'
      AND t.completed_at BETWEEN ${dateRange.start} AND ${dateRange.end}
    GROUP BY t.source_warehouse_id, sw.name, t.destination_warehouse_id, dw.name
    ORDER BY transfer_count DESC
  `;
};
```

## Optimization Suggestions

```typescript
interface OptimizationSuggestion {
  type: 'route' | 'timing' | 'batch' | 'cost';
  title: string;
  description: string;
  potentialSavings?: number;
  priority: 'low' | 'medium' | 'high';
  data: Record<string, any>;
}

export const generateOptimizationSuggestions = async (): Promise<OptimizationSuggestion[]> => {
  const suggestions: OptimizationSuggestion[] = [];

  // Analyze frequent small transfers that could be batched
  const frequentRoutes = await prisma.$queryRaw`
    SELECT
      source_warehouse_id,
      destination_warehouse_id,
      COUNT(*) as transfer_count,
      AVG(total_quantity) as avg_qty
    FROM transfer_requests
    WHERE created_at >= NOW() - INTERVAL '30 days'
      AND status = 'completed'
    GROUP BY source_warehouse_id, destination_warehouse_id
    HAVING COUNT(*) >= 5 AND AVG(total_quantity) < 20
  `;

  for (const route of frequentRoutes) {
    suggestions.push({
      type: 'batch',
      title: 'Consolidate Frequent Small Transfers',
      description: `${route.transfer_count} transfers between these warehouses averaging ${route.avg_qty} items. Consider weekly batching.`,
      priority: 'medium',
      data: route
    });
  }

  // Routes with high discrepancy rates
  const problemRoutes = await prisma.$queryRaw`
    SELECT
      t.source_warehouse_id,
      t.destination_warehouse_id,
      sw.name as source_name,
      dw.name as dest_name,
      COUNT(d.id)::decimal / COUNT(*)  * 100 as discrepancy_rate
    FROM transfer_requests t
    JOIN warehouses sw ON t.source_warehouse_id = sw.id
    JOIN warehouses dw ON t.destination_warehouse_id = dw.id
    LEFT JOIN transfer_discrepancies d ON t.id = d.transfer_id
    WHERE t.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY t.source_warehouse_id, t.destination_warehouse_id, sw.name, dw.name
    HAVING COUNT(d.id)::decimal / COUNT(*) > 0.1
  `;

  for (const route of problemRoutes) {
    suggestions.push({
      type: 'route',
      title: 'High Discrepancy Rate',
      description: `Route from ${route.source_name} to ${route.dest_name} has ${(route.discrepancy_rate).toFixed(1)}% discrepancy rate. Review handling procedures.`,
      priority: 'high',
      data: route
    });
  }

  // Cost optimization
  const costlyRoutes = await prisma.$queryRaw`
    SELECT
      t.source_warehouse_id,
      t.destination_warehouse_id,
      AVG(s.shipping_cost / NULLIF(t.total_quantity, 0)) as cost_per_unit
    FROM transfer_requests t
    JOIN shipments s ON t.id = s.transfer_id
    WHERE t.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY t.source_warehouse_id, t.destination_warehouse_id
    HAVING AVG(s.shipping_cost / NULLIF(t.total_quantity, 0)) > (
      SELECT AVG(shipping_cost / NULLIF(total_quantity, 0)) * 1.5
      FROM transfer_requests t2
      JOIN shipments s2 ON t2.id = s2.transfer_id
    )
  `;

  for (const route of costlyRoutes) {
    suggestions.push({
      type: 'cost',
      title: 'Above Average Shipping Cost',
      description: `Shipping cost per unit on this route is 50%+ above average. Consider alternative carriers or consolidation.`,
      priority: 'medium',
      potentialSavings: route.potential_savings,
      data: route
    });
  }

  return suggestions;
};
```

## Components

### TransferDashboard

```tsx
const TransferDashboard = () => {
  const [dateRange, setDateRange] = useState<DateRange>(last30Days());

  const { data: dashboard } = useQuery({
    queryKey: ['transfer-dashboard', dateRange],
    queryFn: () => fetch(`/api/transfers/analytics?${toQueryString(dateRange)}`).then(r => r.json())
  });

  return (
    <div className="space-y-6">
      {/* Metric cards */}
      <div className="grid grid-cols-4 gap-4">
        <MetricCard
          title="Total Transfers"
          value={dashboard?.metrics.totalTransfers}
          icon={Truck}
        />
        <MetricCard
          title="On-Time Rate"
          value={`${dashboard?.metrics.onTimeRate.toFixed(1)}%`}
          icon={Clock}
          trend={dashboard?.metrics.onTimeRate >= 90 ? 'up' : 'down'}
        />
        <MetricCard
          title="Accuracy Rate"
          value={`${dashboard?.metrics.accuracyRate.toFixed(1)}%`}
          icon={CheckCircle}
        />
        <MetricCard
          title="Avg Lead Time"
          value={`${dashboard?.metrics.avgLeadTimeDays.toFixed(1)} days`}
          icon={Timer}
        />
      </div>

      {/* Route map */}
      <Card>
        <CardHeader>
          <CardTitle>Transfer Routes</CardTitle>
        </CardHeader>
        <CardContent>
          <RouteFlowDiagram routes={dashboard?.byRoute} />
        </CardContent>
      </Card>

      {/* Charts */}
      <div className="grid grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle>Transfer Volume Trend</CardTitle>
          </CardHeader>
          <CardContent>
            <VolumeTrendChart data={dashboard?.trends} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Lead Time Breakdown</CardTitle>
          </CardHeader>
          <CardContent>
            <LeadTimeBreakdownChart data={dashboard?.trends} />
          </CardContent>
        </Card>
      </div>

      {/* Optimization suggestions */}
      <Card>
        <CardHeader>
          <CardTitle>Optimization Opportunities</CardTitle>
        </CardHeader>
        <CardContent>
          <SuggestionsList suggestions={dashboard?.suggestions} />
        </CardContent>
      </Card>
    </div>
  );
};
```

### RoutePerformanceTable

```tsx
const RoutePerformanceTable = ({ routes }: { routes: RouteAnalytics[] }) => (
  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>Route</TableHead>
        <TableHead className="text-right">Transfers</TableHead>
        <TableHead className="text-right">Items</TableHead>
        <TableHead className="text-right">Lead Time</TableHead>
        <TableHead className="text-right">On-Time</TableHead>
        <TableHead className="text-right">Accuracy</TableHead>
        <TableHead className="text-right">Cost/Unit</TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      {routes.map((route) => (
        <TableRow key={`${route.sourceWarehouseId}-${route.destinationWarehouseId}`}>
          <TableCell>
            <div className="flex items-center gap-2">
              <span>{route.sourceName}</span>
              <ArrowRight className="h-4 w-4 text-muted-foreground" />
              <span>{route.destinationName}</span>
            </div>
          </TableCell>
          <TableCell className="text-right">{route.transferCount}</TableCell>
          <TableCell className="text-right">{route.totalQuantity}</TableCell>
          <TableCell className="text-right">
            {route.avgLeadTime.toFixed(1)} days
          </TableCell>
          <TableCell className="text-right">
            <span className={cn(
              route.onTimeRate >= 90 ? 'text-green-600' :
              route.onTimeRate >= 80 ? 'text-yellow-600' : 'text-red-600'
            )}>
              {route.onTimeRate.toFixed(0)}%
            </span>
          </TableCell>
          <TableCell className="text-right">
            <span className={cn(
              route.discrepancyRate <= 5 ? 'text-green-600' :
              route.discrepancyRate <= 10 ? 'text-yellow-600' : 'text-red-600'
            )}>
              {(100 - route.discrepancyRate).toFixed(0)}%
            </span>
          </TableCell>
          <TableCell className="text-right">
            {formatCurrency(route.costPerUnit)}
          </TableCell>
        </TableRow>
      ))}
    </TableBody>
  </Table>
);
```
