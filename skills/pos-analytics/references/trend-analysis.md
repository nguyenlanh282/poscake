# Trend Analysis

Phân tích xu hướng doanh thu và hoạt động kinh doanh theo thời gian.

## Overview

Trend analysis giúp nhận diện patterns trong dữ liệu bán hàng để đưa ra quyết định kinh doanh.

## Time Periods

```typescript
type TrendPeriod =
  | 'hourly'      // By hour of day
  | 'daily'       // By day
  | 'weekly'      // By week
  | 'monthly'     // By month
  | 'quarterly'   // By quarter
  | 'yearly';     // By year

interface TrendDataPoint {
  period: string;
  value: number;
  previousValue?: number;
  change?: number;
}
```

## Trend Types

### 1. Revenue Trend

```typescript
interface RevenueTrend {
  period: string;
  revenue: number;
  orders: number;
  averageOrderValue: number;
  growth: number;
}

// API
const getRevenueTrend = async (
  startDate: Date,
  endDate: Date,
  granularity: TrendPeriod
): Promise<RevenueTrend[]> => {
  return await prisma.$queryRaw`
    SELECT
      DATE_TRUNC(${granularity}, created_at) as period,
      SUM(total_amount) as revenue,
      COUNT(*) as orders,
      AVG(total_amount) as average_order_value
    FROM orders
    WHERE created_at BETWEEN ${startDate} AND ${endDate}
      AND status = 'completed'
    GROUP BY period
    ORDER BY period
  `;
};
```

### 2. Sales by Day of Week

```sql
SELECT
  EXTRACT(DOW FROM created_at) as day_of_week,
  TO_CHAR(created_at, 'Day') as day_name,
  SUM(total_amount) as revenue,
  COUNT(*) as orders
FROM orders
WHERE status = 'completed'
  AND created_at >= NOW() - INTERVAL '3 months'
GROUP BY day_of_week, day_name
ORDER BY day_of_week;
```

### 3. Sales by Hour

```sql
SELECT
  EXTRACT(HOUR FROM created_at) as hour,
  SUM(total_amount) as revenue,
  COUNT(*) as orders
FROM orders
WHERE status = 'completed'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY hour
ORDER BY hour;
```

## Year-over-Year Comparison

```typescript
interface YoYComparison {
  period: string;
  currentYear: number;
  previousYear: number;
  growth: number;
  growthPercent: number;
}

const getYoYComparison = async (year: number): Promise<YoYComparison[]> => {
  return await prisma.$queryRaw`
    WITH current_year AS (
      SELECT
        EXTRACT(MONTH FROM created_at) as month,
        SUM(total_amount) as revenue
      FROM orders
      WHERE EXTRACT(YEAR FROM created_at) = ${year}
        AND status = 'completed'
      GROUP BY month
    ),
    previous_year AS (
      SELECT
        EXTRACT(MONTH FROM created_at) as month,
        SUM(total_amount) as revenue
      FROM orders
      WHERE EXTRACT(YEAR FROM created_at) = ${year - 1}
        AND status = 'completed'
      GROUP BY month
    )
    SELECT
      cy.month,
      cy.revenue as current_year,
      py.revenue as previous_year,
      (cy.revenue - py.revenue) as growth,
      ((cy.revenue - py.revenue) / NULLIF(py.revenue, 0) * 100) as growth_percent
    FROM current_year cy
    LEFT JOIN previous_year py ON cy.month = py.month
    ORDER BY cy.month
  `;
};
```

## Seasonal Trend Detection

```typescript
interface SeasonalPattern {
  period: string;
  expectedValue: number;
  confidence: number;
}

const detectSeasonality = (data: TrendDataPoint[]): SeasonalPattern[] => {
  // Calculate moving average
  const movingAvg = calculateMovingAverage(data, 7);

  // Calculate seasonal indices
  const seasonalIndices = data.map((point, i) => ({
    period: point.period,
    index: point.value / (movingAvg[i] || 1)
  }));

  // Group by season and average
  return aggregateByPeriod(seasonalIndices);
};
```

## Components

### TrendChart

```tsx
import { LineChart, Line, XAxis, YAxis, Tooltip, Legend, ResponsiveContainer } from 'recharts';

interface TrendChartProps {
  data: TrendDataPoint[];
  showComparison?: boolean;
  comparisonData?: TrendDataPoint[];
}

const TrendChart = ({ data, showComparison, comparisonData }: TrendChartProps) => (
  <ResponsiveContainer width="100%" height={300}>
    <LineChart data={data}>
      <XAxis dataKey="period" />
      <YAxis />
      <Tooltip
        formatter={(value) => formatCurrency(value as number)}
      />
      <Legend />
      <Line
        type="monotone"
        dataKey="value"
        stroke="#8884d8"
        name="Current Period"
        strokeWidth={2}
      />
      {showComparison && comparisonData && (
        <Line
          type="monotone"
          data={comparisonData}
          dataKey="value"
          stroke="#82ca9d"
          name="Previous Period"
          strokeDasharray="5 5"
        />
      )}
    </LineChart>
  </ResponsiveContainer>
);
```

### Heatmap for Time-based Patterns

```tsx
const SalesHeatmap = ({ data }: { data: HeatmapData[][] }) => (
  <div className="grid grid-cols-24 gap-1">
    {data.map((row, dayIndex) => (
      <div key={dayIndex} className="flex gap-1">
        {row.map((cell, hourIndex) => (
          <div
            key={hourIndex}
            className="w-4 h-4 rounded"
            style={{
              backgroundColor: getHeatmapColor(cell.value, cell.max)
            }}
            title={`${cell.dayName} ${cell.hour}:00 - ${formatCurrency(cell.value)}`}
          />
        ))}
      </div>
    ))}
  </div>
);
```

## Moving Averages

```typescript
// Simple Moving Average
const calculateSMA = (data: number[], period: number): number[] => {
  return data.map((_, i) => {
    if (i < period - 1) return null;
    const window = data.slice(i - period + 1, i + 1);
    return window.reduce((a, b) => a + b, 0) / period;
  }).filter(Boolean) as number[];
};

// Exponential Moving Average
const calculateEMA = (data: number[], period: number): number[] => {
  const multiplier = 2 / (period + 1);
  const ema: number[] = [data[0]];

  for (let i = 1; i < data.length; i++) {
    ema.push((data[i] - ema[i - 1]) * multiplier + ema[i - 1]);
  }

  return ema;
};
```

## Trend Direction Detection

```typescript
type TrendDirection = 'up' | 'down' | 'stable';

const detectTrendDirection = (data: number[]): TrendDirection => {
  if (data.length < 2) return 'stable';

  // Linear regression slope
  const n = data.length;
  const sumX = (n * (n - 1)) / 2;
  const sumY = data.reduce((a, b) => a + b, 0);
  const sumXY = data.reduce((sum, y, x) => sum + x * y, 0);
  const sumX2 = (n * (n - 1) * (2 * n - 1)) / 6;

  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);

  // Threshold for stable
  const threshold = sumY / n * 0.01; // 1% of average

  if (slope > threshold) return 'up';
  if (slope < -threshold) return 'down';
  return 'stable';
};
```
