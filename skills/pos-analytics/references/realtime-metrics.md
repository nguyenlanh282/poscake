# Real-time Metrics

Live metrics tracking cho POS analytics dashboard.

## Overview

Real-time metrics cho phép theo dõi hoạt động kinh doanh tức thì với cập nhật liên tục qua WebSocket hoặc Server-Sent Events.

## Key Metrics

### Sales Metrics
```typescript
interface SalesMetrics {
  todayRevenue: number;
  todayOrders: number;
  averageOrderValue: number;
  revenueChange: number;      // vs yesterday
  ordersChange: number;
}
```

### Activity Metrics
```typescript
interface ActivityMetrics {
  activeSessions: number;     // Current POS sessions
  activeUsers: number;
  pendingOrders: number;
  processingOrders: number;
}
```

### Conversion Metrics
```typescript
interface ConversionMetrics {
  checkoutStarted: number;
  checkoutCompleted: number;
  conversionRate: number;
  cartAbandonmentRate: number;
}
```

## Implementation

### Server-Sent Events (SSE)

```typescript
// app/api/analytics/realtime/route.ts
export async function GET() {
  const stream = new ReadableStream({
    async start(controller) {
      const sendMetrics = async () => {
        const metrics = await calculateRealtimeMetrics();
        controller.enqueue(`data: ${JSON.stringify(metrics)}\n\n`);
      };

      // Send initial data
      await sendMetrics();

      // Update every 5 seconds
      const interval = setInterval(sendMetrics, 5000);

      return () => clearInterval(interval);
    }
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    }
  });
}
```

### Client Hook

```typescript
// hooks/useRealtimeMetrics.ts
export const useRealtimeMetrics = () => {
  const [metrics, setMetrics] = useState<RealtimeMetrics | null>(null);
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    const eventSource = new EventSource('/api/analytics/realtime');

    eventSource.onopen = () => setIsConnected(true);
    eventSource.onerror = () => setIsConnected(false);

    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      setMetrics(data);
    };

    return () => {
      eventSource.close();
    };
  }, []);

  return { metrics, isConnected };
};
```

## Components

### LiveMetricCard

```tsx
interface LiveMetricCardProps {
  title: string;
  value: number;
  change?: number;
  format?: 'number' | 'currency' | 'percent';
  icon?: React.ReactNode;
}

const LiveMetricCard = ({ title, value, change, format = 'number' }: LiveMetricCardProps) => {
  const formattedValue = useMemo(() => {
    switch (format) {
      case 'currency':
        return new Intl.NumberFormat('vi-VN', {
          style: 'currency',
          currency: 'VND'
        }).format(value);
      case 'percent':
        return `${value.toFixed(1)}%`;
      default:
        return value.toLocaleString();
    }
  }, [value, format]);

  return (
    <Card className="relative overflow-hidden">
      {/* Live indicator */}
      <div className="absolute top-2 right-2">
        <span className="flex h-2 w-2">
          <span className="animate-ping absolute h-2 w-2 rounded-full bg-green-400 opacity-75" />
          <span className="relative rounded-full h-2 w-2 bg-green-500" />
        </span>
      </div>

      <CardContent className="p-4">
        <p className="text-sm text-muted-foreground">{title}</p>
        <p className="text-2xl font-bold">{formattedValue}</p>

        {change !== undefined && (
          <div className={cn(
            "flex items-center text-sm",
            change >= 0 ? "text-green-500" : "text-red-500"
          )}>
            {change >= 0 ? <TrendingUp /> : <TrendingDown />}
            <span>{Math.abs(change).toFixed(1)}%</span>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
```

## Database Queries

### Today's Revenue
```sql
SELECT
  COALESCE(SUM(total_amount), 0) as revenue,
  COUNT(*) as orders,
  COALESCE(AVG(total_amount), 0) as avg_order_value
FROM orders
WHERE DATE(created_at) = CURRENT_DATE
  AND status = 'completed';
```

### Comparison with Yesterday
```sql
WITH today AS (
  SELECT SUM(total_amount) as revenue
  FROM orders
  WHERE DATE(created_at) = CURRENT_DATE
    AND status = 'completed'
),
yesterday AS (
  SELECT SUM(total_amount) as revenue
  FROM orders
  WHERE DATE(created_at) = CURRENT_DATE - INTERVAL '1 day'
    AND status = 'completed'
)
SELECT
  t.revenue as today_revenue,
  y.revenue as yesterday_revenue,
  ((t.revenue - y.revenue) / NULLIF(y.revenue, 0) * 100) as change_percent
FROM today t, yesterday y;
```

## Caching Strategy

```typescript
// Use Redis for cached aggregations
const getCachedMetrics = async () => {
  const cached = await redis.get('realtime:metrics');
  if (cached) return JSON.parse(cached);

  const metrics = await calculateMetrics();
  await redis.setex('realtime:metrics', 5, JSON.stringify(metrics));
  return metrics;
};
```

## Performance Optimization

1. **Aggregate in database** - Use SQL aggregations instead of fetching rows
2. **Cache aggressively** - 5-second cache for real-time is acceptable
3. **Use materialized views** - For complex calculations
4. **Batch updates** - Combine multiple metric updates
5. **Connection pooling** - Limit SSE connections per client
