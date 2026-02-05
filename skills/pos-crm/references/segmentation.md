# Customer Segmentation

Phân loại khách hàng dựa trên RFM và các tiêu chí khác.

## Overview

Segmentation chia khách hàng thành các nhóm dựa trên hành vi mua hàng để có chiến lược marketing và chăm sóc phù hợp.

## RFM Model

RFM = Recency (gần đây) + Frequency (tần suất) + Monetary (giá trị)

```typescript
interface RFMScore {
  customerId: string;
  recency: number;           // Days since last purchase
  frequency: number;         // Total orders
  monetary: number;          // Total spent
  recencyScore: number;      // 1-5 score
  frequencyScore: number;    // 1-5 score
  monetaryScore: number;     // 1-5 score
  rfmScore: string;          // e.g., "555", "321"
  segment: CustomerSegment;
}

type CustomerSegment =
  | 'champion'      // 555, 554, 545
  | 'loyal'         // 543, 444, 435
  | 'potential'     // 512, 511, 422
  | 'new'           // 512, 411, 311
  | 'at_risk'       // 255, 254, 245
  | 'lost';         // 111, 112, 121
```

## RFM Score Calculation

```typescript
// services/segmentation.ts
export const calculateRFMScores = async (): Promise<RFMScore[]> => {
  // Get raw RFM data
  const customers = await prisma.$queryRaw<RFMData[]>`
    SELECT
      customer_id,
      EXTRACT(DAY FROM NOW() - MAX(created_at)) as recency,
      COUNT(*) as frequency,
      SUM(total_amount) as monetary
    FROM orders
    WHERE status = 'completed'
    GROUP BY customer_id
  `;

  // Calculate quintiles for scoring
  const recencies = customers.map(c => c.recency).sort((a, b) => a - b);
  const frequencies = customers.map(c => c.frequency).sort((a, b) => a - b);
  const monetaries = customers.map(c => c.monetary).sort((a, b) => a - b);

  const getQuintile = (value: number, sorted: number[]): number => {
    const index = sorted.indexOf(value);
    const percentile = index / sorted.length;
    return Math.min(5, Math.ceil(percentile * 5) || 1);
  };

  return customers.map(c => {
    // Recency: lower is better, so invert score
    const recencyScore = 6 - getQuintile(c.recency, recencies);
    const frequencyScore = getQuintile(c.frequency, frequencies);
    const monetaryScore = getQuintile(c.monetary, monetaries);

    const rfmScore = `${recencyScore}${frequencyScore}${monetaryScore}`;

    return {
      customerId: c.customer_id,
      recency: c.recency,
      frequency: c.frequency,
      monetary: c.monetary,
      recencyScore,
      frequencyScore,
      monetaryScore,
      rfmScore,
      segment: getRFMSegment(recencyScore, frequencyScore, monetaryScore)
    };
  });
};

const getRFMSegment = (r: number, f: number, m: number): CustomerSegment => {
  const rfmSum = r + f + m;
  const avgFM = (f + m) / 2;

  // Champions: Recent, frequent, high spenders
  if (r >= 4 && f >= 4 && m >= 4) return 'champion';

  // Loyal: Good frequency and spending
  if (f >= 4 && m >= 3) return 'loyal';

  // Potential: Medium-high R but low F/M
  if (r >= 4 && avgFM < 3) return 'potential';

  // New: Very recent, low frequency
  if (r >= 4 && f <= 2) return 'new';

  // At Risk: Haven't purchased recently but were good
  if (r <= 2 && avgFM >= 3) return 'at_risk';

  // Lost: Haven't purchased in long time
  if (r <= 2 && avgFM < 3) return 'lost';

  return 'potential';
};
```

## Segment Definitions

```typescript
const segmentDefinitions = {
  champion: {
    name: 'Champion',
    description: 'Best customers who buy frequently and recently',
    color: '#10b981',
    icon: 'Trophy',
    actions: ['VIP rewards', 'Early access', 'Personal thank you']
  },
  loyal: {
    name: 'Loyal',
    description: 'Regular customers with good spending',
    color: '#3b82f6',
    icon: 'Heart',
    actions: ['Loyalty bonuses', 'Referral program', 'Cross-sell']
  },
  potential: {
    name: 'Potential Loyalist',
    description: 'Recent customers who could become loyal',
    color: '#8b5cf6',
    icon: 'TrendingUp',
    actions: ['Onboarding emails', 'Membership offers', 'Engagement']
  },
  new: {
    name: 'New Customer',
    description: 'Just made first purchase',
    color: '#06b6d4',
    icon: 'UserPlus',
    actions: ['Welcome series', 'First-time offers', 'Product education']
  },
  at_risk: {
    name: 'At Risk',
    description: 'Good customers who haven\'t purchased recently',
    color: '#f59e0b',
    icon: 'AlertTriangle',
    actions: ['Win-back campaign', 'Special offers', 'Personal outreach']
  },
  lost: {
    name: 'Lost',
    description: 'Haven\'t purchased in a long time',
    color: '#ef4444',
    icon: 'UserMinus',
    actions: ['Reactivation campaign', 'Survey why they left', 'Big discount']
  }
};
```

## SQL Segmentation Query

```sql
WITH customer_rfm AS (
  SELECT
    customer_id,
    EXTRACT(DAY FROM NOW() - MAX(created_at)) as recency,
    COUNT(*) as frequency,
    SUM(total_amount) as monetary
  FROM orders
  WHERE status = 'completed'
  GROUP BY customer_id
),
rfm_scores AS (
  SELECT
    customer_id,
    recency,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY recency DESC) as r_score,
    NTILE(5) OVER (ORDER BY frequency) as f_score,
    NTILE(5) OVER (ORDER BY monetary) as m_score
  FROM customer_rfm
)
SELECT
  customer_id,
  recency,
  frequency,
  monetary,
  r_score,
  f_score,
  m_score,
  CONCAT(r_score, f_score, m_score) as rfm_score,
  CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'champion'
    WHEN f_score >= 4 AND m_score >= 3 THEN 'loyal'
    WHEN r_score >= 4 AND f_score <= 2 THEN 'new'
    WHEN r_score >= 4 THEN 'potential'
    WHEN r_score <= 2 AND (f_score + m_score) / 2.0 >= 3 THEN 'at_risk'
    WHEN r_score <= 2 THEN 'lost'
    ELSE 'potential'
  END as segment
FROM rfm_scores;
```

## Custom Segments

```typescript
interface CustomSegment {
  id: string;
  name: string;
  description: string;
  rules: SegmentRule[];
  operator: 'AND' | 'OR';
  customerCount: number;
  createdAt: Date;
}

interface SegmentRule {
  field: string;
  operator: 'eq' | 'neq' | 'gt' | 'gte' | 'lt' | 'lte' | 'in' | 'contains';
  value: any;
}

// Example: High-value customers in Ho Chi Minh
const hcmcVIPSegment: CustomSegment = {
  id: 'hcmc-vip',
  name: 'HCMC VIP',
  description: 'High-value customers in Ho Chi Minh City',
  rules: [
    { field: 'province', operator: 'eq', value: 'HCM' },
    { field: 'lifetimeValue', operator: 'gte', value: 10000000 },
    { field: 'orderCount', operator: 'gte', value: 5 }
  ],
  operator: 'AND',
  customerCount: 0,
  createdAt: new Date()
};
```

## Components

### SegmentBadge

```tsx
const SegmentBadge = ({ segment }: { segment: CustomerSegment }) => {
  const def = segmentDefinitions[segment];
  const Icon = Icons[def.icon];

  return (
    <Badge
      style={{ backgroundColor: def.color }}
      className="text-white"
    >
      <Icon className="h-3 w-3 mr-1" />
      {def.name}
    </Badge>
  );
};
```

### SegmentDistributionChart

```tsx
import { PieChart, Pie, Cell, Legend, ResponsiveContainer } from 'recharts';

const SegmentDistributionChart = ({ data }: { data: SegmentCount[] }) => (
  <ResponsiveContainer width="100%" height={300}>
    <PieChart>
      <Pie
        data={data}
        dataKey="count"
        nameKey="segment"
        cx="50%"
        cy="50%"
        outerRadius={100}
        label={({ name, percent }) => `${name} (${(percent * 100).toFixed(0)}%)`}
      >
        {data.map((entry, index) => (
          <Cell
            key={entry.segment}
            fill={segmentDefinitions[entry.segment].color}
          />
        ))}
      </Pie>
      <Legend />
    </PieChart>
  </ResponsiveContainer>
);
```

### SegmentBuilder

```tsx
const SegmentBuilder = () => {
  const [rules, setRules] = useState<SegmentRule[]>([]);
  const [operator, setOperator] = useState<'AND' | 'OR'>('AND');
  const [preview, setPreview] = useState<number>(0);

  const fields = [
    { value: 'lifetimeValue', label: 'Lifetime Value', type: 'number' },
    { value: 'orderCount', label: 'Order Count', type: 'number' },
    { value: 'lastOrderAt', label: 'Last Order Date', type: 'date' },
    { value: 'loyaltyTier', label: 'Loyalty Tier', type: 'enum' },
    { value: 'province', label: 'Province', type: 'string' },
    { value: 'tags', label: 'Tags', type: 'array' }
  ];

  const previewSegment = async () => {
    const res = await fetch('/api/crm/segments/preview', {
      method: 'POST',
      body: JSON.stringify({ rules, operator })
    });
    const data = await res.json();
    setPreview(data.count);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <span>Match</span>
        <Select value={operator} onValueChange={setOperator}>
          <SelectItem value="AND">ALL</SelectItem>
          <SelectItem value="OR">ANY</SelectItem>
        </Select>
        <span>of the following rules:</span>
      </div>

      {rules.map((rule, index) => (
        <RuleRow
          key={index}
          rule={rule}
          fields={fields}
          onChange={(r) => updateRule(index, r)}
          onRemove={() => removeRule(index)}
        />
      ))}

      <Button variant="outline" onClick={addRule}>
        <Plus className="h-4 w-4 mr-1" /> Add Rule
      </Button>

      <div className="flex items-center justify-between pt-4 border-t">
        <Button variant="secondary" onClick={previewSegment}>
          Preview Segment
        </Button>
        <span className="text-muted-foreground">
          {preview} customers match
        </span>
      </div>
    </div>
  );
};
```

## Auto-update Segments

```typescript
// Background job to recalculate segments
const updateCustomerSegments = async () => {
  const rfmScores = await calculateRFMScores();

  for (const score of rfmScores) {
    await prisma.customer.update({
      where: { id: score.customerId },
      data: {
        segment: score.segment,
        recencyScore: score.recencyScore,
        frequencyScore: score.frequencyScore,
        monetaryScore: score.monetaryScore
      }
    });
  }

  console.log(`Updated segments for ${rfmScores.length} customers`);
};

// Run daily at midnight
cron.schedule('0 0 * * *', updateCustomerSegments);
```
