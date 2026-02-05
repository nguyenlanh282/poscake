---
name: pos-analytics
description: |
  Build business intelligence dashboards for POS systems: real-time metrics (revenue, orders,
  customers), trend analysis (daily/weekly/monthly patterns), forecasting (sales predictions,
  demand planning), cohort analysis (customer behavior over time), funnel analysis (checkout
  conversion), geographic analytics (sales by location). Features: interactive charts, drill-down
  reports, automated alerts, scheduled reports. Use when building BI dashboards, implementing
  advanced analytics, or adding predictive features to retail/restaurant POS.
version: 1.0.0
---

# POS Analytics & Business Intelligence

Build advanced analytics and BI dashboards cho hệ thống POS.

## Analytics Features

### 1. Real-time Metrics
Reference: [references/realtime-metrics.md](references/realtime-metrics.md)
- Live revenue tracking, order count, average order value
- Active sessions, conversion rates
- WebSocket/SSE for live updates

### 2. Trend Analysis
Reference: [references/trend-analysis.md](references/trend-analysis.md)
- Daily/weekly/monthly patterns
- Year-over-year comparison
- Seasonal trend detection

### 3. Forecasting
Reference: [references/forecasting.md](references/forecasting.md)
- Sales predictions using moving averages
- Demand planning for inventory
- Revenue projections

### 4. Cohort Analysis
Reference: [references/cohort-analysis.md](references/cohort-analysis.md)
- Customer retention by signup month
- Purchase behavior over time
- Churn prediction

### 5. Geographic Analytics
Reference: [references/geo-analytics.md](references/geo-analytics.md)
- Sales by region/district
- Delivery zone performance
- Store location optimization

## Tech Stack

- **Charts**: Recharts, Chart.js, D3.js
- **Real-time**: WebSocket, Server-Sent Events
- **Caching**: Redis for aggregated metrics
- **Background Jobs**: Bull for scheduled reports

## Data Models

```typescript
interface AnalyticsMetric {
  id: string;
  name: string;
  value: number;
  previousValue?: number;
  change?: number;        // Percentage change
  changeType?: 'up' | 'down' | 'neutral';
  period: string;
  timestamp: Date;
}

interface TrendDataPoint {
  date: string;
  value: number;
  label?: string;
}

interface CohortData {
  cohort: string;         // e.g., "2024-01"
  period: number;         // Months since signup
  users: number;
  retained: number;
  retentionRate: number;
}
```

## Components

```
components/analytics/
├── Dashboard.tsx            # Main BI dashboard
├── LiveMetrics.tsx          # Real-time metric cards
├── TrendChart.tsx           # Trend visualization
├── ForecastChart.tsx        # Prediction charts
├── CohortTable.tsx          # Cohort retention table
├── HeatmapChart.tsx         # Time-based heatmaps
├── GeoMap.tsx               # Geographic visualization
├── AlertsPanel.tsx          # Metric alerts
└── ScheduledReports.tsx     # Report scheduling UI
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/analytics/realtime` | Live metrics (SSE) |
| GET | `/api/analytics/trends` | Trend data |
| GET | `/api/analytics/forecast` | Predictions |
| GET | `/api/analytics/cohorts` | Cohort analysis |
| GET | `/api/analytics/geo` | Geographic data |
| POST | `/api/analytics/alerts` | Create alert |
| POST | `/api/analytics/reports/schedule` | Schedule report |

## Quick Start

```typescript
// Real-time metrics with SSE
const useRealtimeMetrics = () => {
  const [metrics, setMetrics] = useState<AnalyticsMetric[]>([]);

  useEffect(() => {
    const eventSource = new EventSource('/api/analytics/realtime');
    eventSource.onmessage = (event) => {
      setMetrics(JSON.parse(event.data));
    };
    return () => eventSource.close();
  }, []);

  return metrics;
};
```

## Alert Configuration

```typescript
interface AlertConfig {
  metric: string;
  condition: 'above' | 'below' | 'change';
  threshold: number;
  channels: ('email' | 'sms' | 'push' | 'slack')[];
  frequency: 'immediate' | 'hourly' | 'daily';
}

// Example: Alert when daily revenue drops 20%
const revenueAlert: AlertConfig = {
  metric: 'daily_revenue',
  condition: 'change',
  threshold: -20,
  channels: ['email', 'slack'],
  frequency: 'immediate'
};
```
