---
name: pos-crm
description: |
  Build customer relationship management for POS systems: customer profiles (purchase history,
  preferences, notes), segmentation (VIP, regular, at-risk), loyalty programs (points, tiers,
  rewards), marketing automation (email campaigns, SMS), feedback collection (surveys, reviews),
  customer support (tickets, chat). Use when implementing CRM features, building loyalty systems,
  or adding customer engagement tools to retail/restaurant POS.
version: 1.0.0
---

# POS Customer Relationship Management

Build comprehensive CRM features cho hệ thống POS.

## CRM Features

### 1. Customer Profiles
Reference: [references/customer-profiles.md](references/customer-profiles.md)
- Complete purchase history
- Preferences and notes
- Communication history
- Custom fields

### 2. Segmentation
Reference: [references/segmentation.md](references/segmentation.md)
- RFM-based segmentation (Recency, Frequency, Monetary)
- VIP/Regular/At-risk classification
- Custom segment rules

### 3. Loyalty Programs
Reference: [references/loyalty.md](references/loyalty.md)
- Points accumulation and redemption
- Tier system (Bronze, Silver, Gold, Platinum)
- Reward catalog
- Birthday/anniversary rewards

### 4. Marketing Automation
Reference: [references/marketing.md](references/marketing.md)
- Email campaigns (Resend, SendGrid)
- SMS marketing (Twilio)
- Trigger-based automation
- A/B testing

### 5. Feedback & Support
Reference: [references/feedback.md](references/feedback.md)
- Post-purchase surveys
- Review collection
- Support tickets
- Live chat integration

## Data Models

```typescript
interface Customer {
  id: string;
  name: string;
  email?: string;
  phone: string;

  // CRM fields
  segment: CustomerSegment;
  loyaltyTier: LoyaltyTier;
  loyaltyPoints: number;
  lifetimeValue: number;

  // RFM scores
  recencyScore: number;    // Days since last purchase
  frequencyScore: number;  // Order count
  monetaryScore: number;   // Total spent

  // Preferences
  preferredChannel: 'email' | 'sms' | 'push';
  marketingConsent: boolean;
  notes: string;
  tags: string[];

  // Dates
  firstPurchaseAt?: Date;
  lastPurchaseAt?: Date;
  createdAt: Date;
}

type CustomerSegment = 'champion' | 'loyal' | 'potential' | 'new' | 'at_risk' | 'lost';
type LoyaltyTier = 'bronze' | 'silver' | 'gold' | 'platinum';

interface LoyaltyTransaction {
  id: string;
  customerId: string;
  type: 'earn' | 'redeem' | 'expire' | 'adjust';
  points: number;
  balance: number;
  orderId?: string;
  description: string;
  createdAt: Date;
}
```

## Components

```
components/crm/
├── CustomerProfile.tsx       # Full customer view
├── CustomerList.tsx          # Searchable customer list
├── SegmentBadge.tsx          # Segment indicator
├── LoyaltyCard.tsx           # Points and tier display
├── LoyaltyHistory.tsx        # Transaction history
├── PointsRedemption.tsx      # Redeem points at checkout
├── CampaignBuilder.tsx       # Create marketing campaigns
├── SegmentBuilder.tsx        # Define custom segments
├── SurveyBuilder.tsx         # Create feedback surveys
└── CustomerSupport.tsx       # Support ticket management
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/crm/customers` | List customers |
| GET | `/api/crm/customers/:id` | Customer profile |
| PUT | `/api/crm/customers/:id` | Update customer |
| GET | `/api/crm/segments` | List segments |
| POST | `/api/crm/segments` | Create segment |
| GET | `/api/crm/loyalty/balance/:customerId` | Points balance |
| POST | `/api/crm/loyalty/earn` | Earn points |
| POST | `/api/crm/loyalty/redeem` | Redeem points |
| POST | `/api/crm/campaigns` | Create campaign |
| GET | `/api/crm/campaigns/:id/stats` | Campaign statistics |

## Loyalty Configuration

```typescript
const loyaltyConfig = {
  // Points earning
  pointsPerAmount: 1,        // 1 point per 1000 VND
  amountUnit: 1000,

  // Tier thresholds (lifetime points)
  tiers: {
    bronze: 0,
    silver: 1000,
    gold: 5000,
    platinum: 20000
  },

  // Tier multipliers
  multipliers: {
    bronze: 1,
    silver: 1.2,
    gold: 1.5,
    platinum: 2
  },

  // Point expiration
  expirationMonths: 12,

  // Redemption
  pointValue: 10,            // 1 point = 10 VND discount
  minRedemption: 100         // Minimum points to redeem
};
```

## RFM Segmentation

```typescript
const calculateRFMSegment = (customer: Customer): CustomerSegment => {
  const { recencyScore, frequencyScore, monetaryScore } = customer;
  const total = recencyScore + frequencyScore + monetaryScore;

  if (total >= 12) return 'champion';
  if (total >= 9) return 'loyal';
  if (total >= 6) return 'potential';
  if (recencyScore <= 2) return 'at_risk';
  if (recencyScore <= 1 && frequencyScore <= 2) return 'lost';
  return 'new';
};
```

## Marketing Automation

```typescript
// Trigger-based automation
const automations = [
  {
    trigger: 'first_purchase',
    delay: '1d',
    action: 'send_email',
    template: 'welcome'
  },
  {
    trigger: 'no_purchase_30d',
    delay: '0',
    action: 'send_sms',
    template: 'win_back'
  },
  {
    trigger: 'birthday',
    delay: '-1d',
    action: 'send_email',
    template: 'birthday_offer'
  }
];
```
