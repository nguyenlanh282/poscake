# Geographic Analytics

Phân tích dữ liệu theo vị trí địa lý cho POS systems.

## Overview

Geographic analytics giúp hiểu hiệu suất bán hàng theo vùng địa lý, tối ưu delivery zones, và đưa ra quyết định về mở rộng chi nhánh.

## Data Model

```typescript
interface GeoSalesData {
  regionCode: string;         // Province/City code
  regionName: string;
  districtCode?: string;
  districtName?: string;
  revenue: number;
  orders: number;
  customers: number;
  averageOrderValue: number;
}

interface StorePerformance {
  storeId: string;
  storeName: string;
  address: string;
  latitude: number;
  longitude: number;
  revenue: number;
  orders: number;
  growth: number;
}

interface DeliveryZone {
  zoneId: string;
  zoneName: string;
  polygon: GeoJSON.Polygon;
  deliveryFee: number;
  estimatedTime: number;
  orders: number;
  avgDeliveryTime: number;
}
```

## SQL Queries

### Sales by Province

```sql
SELECT
  c.province_code,
  c.province_name,
  COUNT(DISTINCT o.id) as orders,
  COUNT(DISTINCT o.customer_id) as customers,
  SUM(o.total_amount) as revenue,
  AVG(o.total_amount) as avg_order_value
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.status = 'completed'
  AND o.created_at >= NOW() - INTERVAL '30 days'
GROUP BY c.province_code, c.province_name
ORDER BY revenue DESC;
```

### Sales by District

```sql
SELECT
  c.province_code,
  c.district_code,
  c.district_name,
  COUNT(DISTINCT o.id) as orders,
  SUM(o.total_amount) as revenue
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.status = 'completed'
  AND c.province_code = $1
GROUP BY c.province_code, c.district_code, c.district_name
ORDER BY revenue DESC;
```

### Store Performance

```sql
SELECT
  s.id,
  s.name,
  s.address,
  s.latitude,
  s.longitude,
  COUNT(o.id) as orders,
  SUM(o.total_amount) as revenue,
  (
    (SUM(CASE WHEN o.created_at >= NOW() - INTERVAL '30 days' THEN o.total_amount ELSE 0 END) -
     SUM(CASE WHEN o.created_at >= NOW() - INTERVAL '60 days' AND o.created_at < NOW() - INTERVAL '30 days' THEN o.total_amount ELSE 0 END))
    / NULLIF(SUM(CASE WHEN o.created_at >= NOW() - INTERVAL '60 days' AND o.created_at < NOW() - INTERVAL '30 days' THEN o.total_amount ELSE 0 END), 0)
    * 100
  ) as growth_percent
FROM stores s
LEFT JOIN orders o ON s.id = o.store_id AND o.status = 'completed'
GROUP BY s.id, s.name, s.address, s.latitude, s.longitude
ORDER BY revenue DESC;
```

## Implementation

### Geo Analytics Service

```typescript
// services/geoAnalytics.ts
export const getRegionalSales = async (
  period: DateRange,
  level: 'province' | 'district'
): Promise<GeoSalesData[]> => {
  if (level === 'province') {
    return await prisma.$queryRaw`
      SELECT
        c.province_code as region_code,
        c.province_name as region_name,
        COUNT(DISTINCT o.id) as orders,
        COUNT(DISTINCT o.customer_id) as customers,
        COALESCE(SUM(o.total_amount), 0) as revenue,
        COALESCE(AVG(o.total_amount), 0) as average_order_value
      FROM orders o
      JOIN customers c ON o.customer_id = c.id
      WHERE o.status = 'completed'
        AND o.created_at BETWEEN ${period.start} AND ${period.end}
      GROUP BY c.province_code, c.province_name
    `;
  }

  return await prisma.$queryRaw`
    SELECT
      c.district_code as region_code,
      c.district_name as region_name,
      c.province_code,
      COUNT(DISTINCT o.id) as orders,
      COUNT(DISTINCT o.customer_id) as customers,
      COALESCE(SUM(o.total_amount), 0) as revenue,
      COALESCE(AVG(o.total_amount), 0) as average_order_value
    FROM orders o
    JOIN customers c ON o.customer_id = c.id
    WHERE o.status = 'completed'
      AND o.created_at BETWEEN ${period.start} AND ${period.end}
    GROUP BY c.district_code, c.district_name, c.province_code
  `;
};
```

### Delivery Zone Analysis

```typescript
export const analyzeDeliveryZones = async (): Promise<DeliveryZone[]> => {
  const zones = await prisma.deliveryZone.findMany({
    include: {
      orders: {
        where: { status: 'delivered' },
        select: {
          id: true,
          deliveryTime: true,
          createdAt: true,
          deliveredAt: true
        }
      }
    }
  });

  return zones.map(zone => ({
    zoneId: zone.id,
    zoneName: zone.name,
    polygon: zone.polygon,
    deliveryFee: zone.deliveryFee,
    estimatedTime: zone.estimatedTime,
    orders: zone.orders.length,
    avgDeliveryTime: zone.orders.length > 0
      ? zone.orders.reduce((sum, o) =>
          sum + differenceInMinutes(o.deliveredAt, o.createdAt), 0
        ) / zone.orders.length
      : 0
  }));
};
```

## Components

### Vietnam Map with Sales Data

```tsx
import { MapContainer, TileLayer, GeoJSON, Tooltip } from 'react-leaflet';
import vietnamProvinces from '@/data/vietnam-provinces.json';

interface GeoMapProps {
  data: GeoSalesData[];
}

const GeoMap = ({ data }: GeoMapProps) => {
  const getColor = (revenue: number, max: number) => {
    const ratio = revenue / max;
    if (ratio > 0.8) return '#084081';
    if (ratio > 0.6) return '#0868ac';
    if (ratio > 0.4) return '#2b8cbe';
    if (ratio > 0.2) return '#4eb3d3';
    return '#7bccc4';
  };

  const maxRevenue = Math.max(...data.map(d => d.revenue));

  const style = (feature: GeoJSON.Feature) => {
    const regionData = data.find(
      d => d.regionCode === feature.properties.code
    );
    return {
      fillColor: regionData ? getColor(regionData.revenue, maxRevenue) : '#eee',
      weight: 1,
      opacity: 1,
      color: 'white',
      fillOpacity: 0.7
    };
  };

  const onEachFeature = (feature: GeoJSON.Feature, layer: L.Layer) => {
    const regionData = data.find(
      d => d.regionCode === feature.properties.code
    );
    if (regionData) {
      layer.bindTooltip(`
        <strong>${regionData.regionName}</strong><br/>
        Revenue: ${formatCurrency(regionData.revenue)}<br/>
        Orders: ${regionData.orders}
      `);
    }
  };

  return (
    <MapContainer
      center={[16.0, 107.0]}
      zoom={6}
      style={{ height: '500px', width: '100%' }}
    >
      <TileLayer
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <GeoJSON
        data={vietnamProvinces}
        style={style}
        onEachFeature={onEachFeature}
      />
    </MapContainer>
  );
};
```

### Store Location Map

```tsx
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import { Icon } from 'leaflet';

const StoreMap = ({ stores }: { stores: StorePerformance[] }) => {
  const getMarkerIcon = (growth: number) => {
    const color = growth >= 0 ? 'green' : 'red';
    return new Icon({
      iconUrl: `/markers/${color}-marker.png`,
      iconSize: [25, 41]
    });
  };

  return (
    <MapContainer center={[21.0285, 105.8542]} zoom={12}>
      <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
      {stores.map(store => (
        <Marker
          key={store.storeId}
          position={[store.latitude, store.longitude]}
          icon={getMarkerIcon(store.growth)}
        >
          <Popup>
            <div>
              <h3 className="font-bold">{store.storeName}</h3>
              <p>{store.address}</p>
              <p>Revenue: {formatCurrency(store.revenue)}</p>
              <p>Orders: {store.orders}</p>
              <p className={store.growth >= 0 ? 'text-green-600' : 'text-red-600'}>
                Growth: {store.growth.toFixed(1)}%
              </p>
            </div>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
};
```

## Heat Map Analysis

```typescript
interface HeatmapPoint {
  lat: number;
  lng: number;
  weight: number;
}

const generateOrderHeatmap = async (
  bounds: LatLngBounds,
  period: DateRange
): Promise<HeatmapPoint[]> => {
  const orders = await prisma.order.findMany({
    where: {
      status: 'completed',
      createdAt: { gte: period.start, lte: period.end },
      deliveryLat: { gte: bounds.south, lte: bounds.north },
      deliveryLng: { gte: bounds.west, lte: bounds.east }
    },
    select: {
      deliveryLat: true,
      deliveryLng: true,
      totalAmount: true
    }
  });

  return orders.map(o => ({
    lat: o.deliveryLat,
    lng: o.deliveryLng,
    weight: o.totalAmount / 1000000 // Normalize
  }));
};
```

## Store Location Optimization

```typescript
interface LocationScore {
  lat: number;
  lng: number;
  score: number;
  factors: {
    demandDensity: number;
    competitorDistance: number;
    accessibilityScore: number;
  };
}

const analyzeNewStoreLocation = async (
  candidates: { lat: number; lng: number }[]
): Promise<LocationScore[]> => {
  return Promise.all(candidates.map(async (loc) => {
    // Calculate demand in 3km radius
    const nearbyOrders = await getOrdersInRadius(loc, 3);
    const demandDensity = nearbyOrders.length;

    // Check competitor distance
    const nearestCompetitor = await getNearestCompetitor(loc);
    const competitorDistance = nearestCompetitor?.distance ?? 10;

    // Accessibility (main roads, parking)
    const accessibilityScore = await calculateAccessibility(loc);

    const score =
      demandDensity * 0.5 +
      Math.min(competitorDistance, 5) * 0.3 +
      accessibilityScore * 0.2;

    return {
      ...loc,
      score,
      factors: { demandDensity, competitorDistance, accessibilityScore }
    };
  }));
};
```
