# Forecasting

Dự báo doanh thu và nhu cầu hàng hóa cho POS systems.

## Overview

Forecasting giúp dự đoán doanh số và nhu cầu trong tương lai để lập kế hoạch kinh doanh và quản lý tồn kho.

## Forecasting Methods

### 1. Simple Moving Average

```typescript
const forecastSMA = (
  historicalData: number[],
  periods: number,
  forecastPeriods: number
): number[] => {
  const lastWindow = historicalData.slice(-periods);
  const average = lastWindow.reduce((a, b) => a + b, 0) / periods;

  return Array(forecastPeriods).fill(average);
};
```

### 2. Weighted Moving Average

```typescript
const forecastWMA = (
  historicalData: number[],
  weights: number[],
  forecastPeriods: number
): number[] => {
  const periods = weights.length;
  const lastWindow = historicalData.slice(-periods);

  const weightedSum = lastWindow.reduce(
    (sum, value, i) => sum + value * weights[i],
    0
  );
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  const forecast = weightedSum / totalWeight;

  return Array(forecastPeriods).fill(forecast);
};

// Example: More weight on recent data
const weights = [0.1, 0.15, 0.2, 0.25, 0.3]; // Last period has highest weight
```

### 3. Exponential Smoothing

```typescript
interface ExponentialSmoothingParams {
  alpha: number;   // Level smoothing (0-1)
  beta?: number;   // Trend smoothing (optional)
  gamma?: number;  // Seasonal smoothing (optional)
  seasonLength?: number;
}

const forecastExponentialSmoothing = (
  data: number[],
  params: ExponentialSmoothingParams,
  periods: number
): number[] => {
  const { alpha } = params;

  // Simple exponential smoothing
  let level = data[0];

  for (let i = 1; i < data.length; i++) {
    level = alpha * data[i] + (1 - alpha) * level;
  }

  // Forecast is last smoothed level
  return Array(periods).fill(level);
};

// Holt's method (with trend)
const forecastHolt = (
  data: number[],
  alpha: number,
  beta: number,
  periods: number
): number[] => {
  let level = data[0];
  let trend = data[1] - data[0];

  for (let i = 1; i < data.length; i++) {
    const prevLevel = level;
    level = alpha * data[i] + (1 - alpha) * (level + trend);
    trend = beta * (level - prevLevel) + (1 - beta) * trend;
  }

  // Forecast with trend
  return Array.from({ length: periods }, (_, i) => level + (i + 1) * trend);
};
```

### 4. Seasonal Decomposition

```typescript
interface SeasonalForecast {
  trend: number[];
  seasonal: number[];
  forecast: number[];
}

const forecastSeasonal = (
  data: number[],
  seasonLength: number,
  periods: number
): SeasonalForecast => {
  // Calculate seasonal indices
  const seasonalIndices: number[] = [];
  for (let s = 0; s < seasonLength; s++) {
    const seasonValues = data.filter((_, i) => i % seasonLength === s);
    const avg = seasonValues.reduce((a, b) => a + b, 0) / seasonValues.length;
    const overallAvg = data.reduce((a, b) => a + b, 0) / data.length;
    seasonalIndices.push(avg / overallAvg);
  }

  // Deseasonalize
  const deseasonalized = data.map((v, i) => v / seasonalIndices[i % seasonLength]);

  // Fit trend to deseasonalized data
  const trendCoeffs = linearRegression(deseasonalized);

  // Generate forecast
  const forecast: number[] = [];
  for (let i = 0; i < periods; i++) {
    const trendValue = trendCoeffs.slope * (data.length + i) + trendCoeffs.intercept;
    const seasonIndex = (data.length + i) % seasonLength;
    forecast.push(trendValue * seasonalIndices[seasonIndex]);
  }

  return {
    trend: trendCoeffs,
    seasonal: seasonalIndices,
    forecast
  };
};
```

## Revenue Forecasting

```typescript
interface RevenueForecast {
  date: string;
  predicted: number;
  lowerBound: number;
  upperBound: number;
  confidence: number;
}

const forecastRevenue = async (
  days: number,
  confidenceLevel: number = 0.95
): Promise<RevenueForecast[]> => {
  // Get historical data
  const historical = await getHistoricalRevenue(90); // Last 90 days

  // Apply Holt-Winters seasonal
  const seasonLength = 7; // Weekly seasonality
  const { forecast } = forecastSeasonal(
    historical.map(h => h.revenue),
    seasonLength,
    days
  );

  // Calculate prediction intervals
  const stdDev = calculateStdDev(historical.map(h => h.revenue));
  const zScore = getZScore(confidenceLevel);

  return forecast.map((predicted, i) => ({
    date: addDays(new Date(), i + 1).toISOString(),
    predicted,
    lowerBound: predicted - zScore * stdDev,
    upperBound: predicted + zScore * stdDev,
    confidence: confidenceLevel
  }));
};
```

## Demand Forecasting for Inventory

```typescript
interface DemandForecast {
  productId: string;
  productName: string;
  currentStock: number;
  forecastedDemand: number;
  suggestedReorder: number;
  reorderDate: Date;
  stockoutRisk: 'low' | 'medium' | 'high';
}

const forecastProductDemand = async (
  productId: string,
  days: number
): Promise<DemandForecast> => {
  // Get sales history
  const salesHistory = await getProductSalesHistory(productId, 90);

  // Forecast demand
  const dailySales = salesHistory.map(s => s.quantity);
  const forecast = forecastExponentialSmoothing(
    dailySales,
    { alpha: 0.3 },
    days
  );

  const forecastedDemand = forecast.reduce((a, b) => a + b, 0);
  const currentStock = await getStockLevel(productId);

  // Calculate reorder point
  const avgDailySales = dailySales.reduce((a, b) => a + b, 0) / dailySales.length;
  const leadTimeDays = 7;
  const safetyStock = avgDailySales * 3; // 3 days safety stock
  const reorderPoint = avgDailySales * leadTimeDays + safetyStock;

  // Determine stockout risk
  const daysUntilStockout = currentStock / avgDailySales;
  const stockoutRisk =
    daysUntilStockout <= 3 ? 'high' :
    daysUntilStockout <= 7 ? 'medium' : 'low';

  return {
    productId,
    productName: await getProductName(productId),
    currentStock,
    forecastedDemand,
    suggestedReorder: Math.max(0, forecastedDemand - currentStock + safetyStock),
    reorderDate: addDays(new Date(), daysUntilStockout - leadTimeDays),
    stockoutRisk
  };
};
```

## Components

### ForecastChart

```tsx
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

const ForecastChart = ({ historical, forecast }: ForecastChartProps) => {
  const data = [
    ...historical.map(h => ({ ...h, type: 'historical' })),
    ...forecast.map(f => ({ ...f, type: 'forecast' }))
  ];

  return (
    <ResponsiveContainer width="100%" height={300}>
      <AreaChart data={data}>
        <XAxis dataKey="date" />
        <YAxis />
        <Tooltip />

        {/* Confidence interval */}
        <Area
          type="monotone"
          dataKey="upperBound"
          stroke="none"
          fill="#8884d8"
          fillOpacity={0.1}
        />
        <Area
          type="monotone"
          dataKey="lowerBound"
          stroke="none"
          fill="#fff"
        />

        {/* Forecast line */}
        <Area
          type="monotone"
          dataKey="predicted"
          stroke="#8884d8"
          fill="#8884d8"
          fillOpacity={0.3}
          strokeDasharray="5 5"
        />

        {/* Historical line */}
        <Area
          type="monotone"
          dataKey="actual"
          stroke="#82ca9d"
          fill="#82ca9d"
          fillOpacity={0.5}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
};
```

## Forecast Accuracy Metrics

```typescript
interface ForecastAccuracy {
  mae: number;    // Mean Absolute Error
  mape: number;   // Mean Absolute Percentage Error
  rmse: number;   // Root Mean Square Error
}

const calculateAccuracy = (
  actual: number[],
  predicted: number[]
): ForecastAccuracy => {
  const n = actual.length;

  const mae = actual.reduce((sum, a, i) => sum + Math.abs(a - predicted[i]), 0) / n;

  const mape = actual.reduce(
    (sum, a, i) => sum + Math.abs((a - predicted[i]) / a),
    0
  ) / n * 100;

  const mse = actual.reduce(
    (sum, a, i) => sum + Math.pow(a - predicted[i], 2),
    0
  ) / n;
  const rmse = Math.sqrt(mse);

  return { mae, mape, rmse };
};
```
