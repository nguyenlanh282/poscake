# Loyalty Programs

Xây dựng chương trình loyalty với điểm thưởng và tiers.

## Overview

Loyalty program giúp tăng customer retention bằng cách thưởng điểm cho mỗi giao dịch và cung cấp benefits theo tier.

## Configuration

```typescript
interface LoyaltyConfig {
  // Points earning
  earning: {
    pointsPerAmount: number;     // Points per currency unit
    amountUnit: number;          // Currency unit (e.g., 1000 VND)
    bonusEvents: BonusEvent[];   // Special earning events
  };

  // Tiers
  tiers: LoyaltyTier[];

  // Redemption
  redemption: {
    pointValue: number;          // Currency value per point
    minPoints: number;           // Minimum to redeem
    maxPercentage: number;       // Max % of order can be paid with points
  };

  // Expiration
  expiration: {
    enabled: boolean;
    months: number;              // Points expire after X months
  };
}

interface LoyaltyTier {
  id: string;
  name: string;
  threshold: number;             // Points needed to reach tier
  multiplier: number;            // Earning multiplier
  benefits: string[];
  color: string;
  icon: string;
}

interface BonusEvent {
  type: 'birthday' | 'anniversary' | 'referral' | 'review' | 'firstPurchase';
  points: number;
  description: string;
}

// Default config
const defaultLoyaltyConfig: LoyaltyConfig = {
  earning: {
    pointsPerAmount: 1,
    amountUnit: 1000,            // 1 point per 1000 VND
    bonusEvents: [
      { type: 'birthday', points: 100, description: 'Birthday bonus' },
      { type: 'firstPurchase', points: 50, description: 'First purchase bonus' },
      { type: 'referral', points: 200, description: 'Referral bonus' },
      { type: 'review', points: 20, description: 'Review bonus' }
    ]
  },
  tiers: [
    {
      id: 'bronze',
      name: 'Bronze',
      threshold: 0,
      multiplier: 1,
      benefits: ['Earn 1 point per 1000 VND'],
      color: '#cd7f32',
      icon: 'Award'
    },
    {
      id: 'silver',
      name: 'Silver',
      threshold: 1000,
      multiplier: 1.2,
      benefits: ['Earn 1.2x points', '5% birthday discount'],
      color: '#c0c0c0',
      icon: 'Award'
    },
    {
      id: 'gold',
      name: 'Gold',
      threshold: 5000,
      multiplier: 1.5,
      benefits: ['Earn 1.5x points', '10% birthday discount', 'Free delivery'],
      color: '#ffd700',
      icon: 'Crown'
    },
    {
      id: 'platinum',
      name: 'Platinum',
      threshold: 20000,
      multiplier: 2,
      benefits: ['Earn 2x points', '15% birthday discount', 'Free delivery', 'Priority support'],
      color: '#e5e4e2',
      icon: 'Gem'
    }
  ],
  redemption: {
    pointValue: 10,              // 1 point = 10 VND
    minPoints: 100,
    maxPercentage: 50            // Max 50% of order
  },
  expiration: {
    enabled: true,
    months: 12
  }
};
```

## Data Model

```typescript
interface LoyaltyTransaction {
  id: string;
  customerId: string;
  type: 'earn' | 'redeem' | 'expire' | 'adjust' | 'bonus';
  points: number;                // Positive for earn, negative for redeem
  balance: number;               // Balance after transaction
  orderId?: string;
  description: string;
  expiresAt?: Date;
  createdAt: Date;
}

interface CustomerLoyalty {
  customerId: string;
  currentPoints: number;
  lifetimePoints: number;
  tier: LoyaltyTier;
  nextTier?: LoyaltyTier;
  pointsToNextTier: number;
  expiringPoints: {
    points: number;
    expiresAt: Date;
  }[];
}
```

## Database Schema

```prisma
model LoyaltyTransaction {
  id          String   @id @default(cuid())
  customerId  String
  customer    Customer @relation(fields: [customerId], references: [id])

  type        LoyaltyTransactionType
  points      Int
  balance     Int
  orderId     String?
  order       Order?   @relation(fields: [orderId], references: [id])

  description String
  expiresAt   DateTime?
  createdAt   DateTime @default(now())

  @@index([customerId])
  @@index([orderId])
  @@index([expiresAt])
}

enum LoyaltyTransactionType {
  EARN
  REDEEM
  EXPIRE
  ADJUST
  BONUS
}
```

## Service Implementation

```typescript
// services/loyalty.ts

export const earnPoints = async (
  customerId: string,
  orderId: string,
  orderAmount: number
): Promise<LoyaltyTransaction> => {
  const config = await getLoyaltyConfig();
  const customer = await prisma.customer.findUnique({
    where: { id: customerId }
  });

  // Calculate base points
  const basePoints = Math.floor(orderAmount / config.earning.amountUnit)
    * config.earning.pointsPerAmount;

  // Apply tier multiplier
  const tierConfig = config.tiers.find(t => t.id === customer.loyaltyTier);
  const earnedPoints = Math.floor(basePoints * (tierConfig?.multiplier || 1));

  // Calculate expiration date
  const expiresAt = config.expiration.enabled
    ? addMonths(new Date(), config.expiration.months)
    : undefined;

  // Create transaction
  const newBalance = customer.loyaltyPoints + earnedPoints;

  const transaction = await prisma.loyaltyTransaction.create({
    data: {
      customerId,
      orderId,
      type: 'EARN',
      points: earnedPoints,
      balance: newBalance,
      description: `Earned from order`,
      expiresAt
    }
  });

  // Update customer
  await prisma.customer.update({
    where: { id: customerId },
    data: {
      loyaltyPoints: newBalance,
      lifetimePoints: { increment: earnedPoints }
    }
  });

  // Check tier upgrade
  await checkTierUpgrade(customerId);

  return transaction;
};

export const redeemPoints = async (
  customerId: string,
  points: number,
  orderId: string
): Promise<{ transaction: LoyaltyTransaction; discount: number }> => {
  const config = await getLoyaltyConfig();
  const customer = await prisma.customer.findUnique({
    where: { id: customerId }
  });

  // Validate
  if (points < config.redemption.minPoints) {
    throw new Error(`Minimum ${config.redemption.minPoints} points required`);
  }
  if (points > customer.loyaltyPoints) {
    throw new Error('Insufficient points');
  }

  const discount = points * config.redemption.pointValue;
  const newBalance = customer.loyaltyPoints - points;

  const transaction = await prisma.loyaltyTransaction.create({
    data: {
      customerId,
      orderId,
      type: 'REDEEM',
      points: -points,
      balance: newBalance,
      description: `Redeemed for discount`
    }
  });

  await prisma.customer.update({
    where: { id: customerId },
    data: { loyaltyPoints: newBalance }
  });

  return { transaction, discount };
};

export const awardBonusPoints = async (
  customerId: string,
  bonusType: BonusEvent['type']
): Promise<LoyaltyTransaction | null> => {
  const config = await getLoyaltyConfig();
  const bonus = config.earning.bonusEvents.find(b => b.type === bonusType);

  if (!bonus) return null;

  const customer = await prisma.customer.findUnique({
    where: { id: customerId }
  });

  const newBalance = customer.loyaltyPoints + bonus.points;
  const expiresAt = config.expiration.enabled
    ? addMonths(new Date(), config.expiration.months)
    : undefined;

  const transaction = await prisma.loyaltyTransaction.create({
    data: {
      customerId,
      type: 'BONUS',
      points: bonus.points,
      balance: newBalance,
      description: bonus.description,
      expiresAt
    }
  });

  await prisma.customer.update({
    where: { id: customerId },
    data: {
      loyaltyPoints: newBalance,
      lifetimePoints: { increment: bonus.points }
    }
  });

  return transaction;
};

const checkTierUpgrade = async (customerId: string) => {
  const config = await getLoyaltyConfig();
  const customer = await prisma.customer.findUnique({
    where: { id: customerId }
  });

  // Find appropriate tier based on lifetime points
  const newTier = [...config.tiers]
    .reverse()
    .find(t => customer.lifetimePoints >= t.threshold);

  if (newTier && newTier.id !== customer.loyaltyTier) {
    await prisma.customer.update({
      where: { id: customerId },
      data: { loyaltyTier: newTier.id }
    });

    // Send tier upgrade notification
    await sendNotification(customerId, {
      type: 'tier_upgrade',
      title: `Congratulations! You're now ${newTier.name}!`,
      body: `Enjoy your new benefits: ${newTier.benefits.join(', ')}`
    });
  }
};
```

## Components

### LoyaltyCard

```tsx
const LoyaltyCard = ({ customer }: { customer: CustomerLoyalty }) => (
  <Card className={cn(
    "bg-gradient-to-br",
    getTierGradient(customer.tier.id)
  )}>
    <CardContent className="p-6 text-white">
      <div className="flex justify-between items-start mb-6">
        <div>
          <p className="text-sm opacity-80">Loyalty Points</p>
          <p className="text-3xl font-bold">{customer.currentPoints.toLocaleString()}</p>
        </div>
        <Badge className="bg-white/20">{customer.tier.name}</Badge>
      </div>

      {customer.nextTier && (
        <div className="mb-4">
          <div className="flex justify-between text-sm mb-1">
            <span>{customer.tier.name}</span>
            <span>{customer.nextTier.name}</span>
          </div>
          <Progress
            value={(customer.lifetimePoints / customer.nextTier.threshold) * 100}
            className="h-2 bg-white/20"
          />
          <p className="text-xs mt-1 opacity-80">
            {customer.pointsToNextTier.toLocaleString()} points to next tier
          </p>
        </div>
      )}

      {customer.expiringPoints.length > 0 && (
        <div className="text-sm bg-white/10 rounded p-2">
          <p className="font-medium">Expiring soon:</p>
          {customer.expiringPoints.slice(0, 2).map((exp, i) => (
            <p key={i} className="text-xs opacity-80">
              {exp.points} points on {formatDate(exp.expiresAt)}
            </p>
          ))}
        </div>
      )}
    </CardContent>
  </Card>
);
```

### PointsRedemption at Checkout

```tsx
const PointsRedemption = ({
  customer,
  orderTotal,
  onRedeem
}: {
  customer: CustomerLoyalty;
  orderTotal: number;
  onRedeem: (points: number, discount: number) => void;
}) => {
  const config = useLoyaltyConfig();
  const [points, setPoints] = useState(0);

  const maxRedeemable = Math.min(
    customer.currentPoints,
    Math.floor(orderTotal * config.redemption.maxPercentage / 100 / config.redemption.pointValue)
  );

  const discount = points * config.redemption.pointValue;

  return (
    <div className="border rounded p-4">
      <div className="flex justify-between items-center mb-4">
        <span className="font-medium">Use Loyalty Points</span>
        <span className="text-sm text-muted-foreground">
          Available: {customer.currentPoints.toLocaleString()} pts
        </span>
      </div>

      <div className="flex items-center gap-4">
        <Slider
          value={[points]}
          max={maxRedeemable}
          step={10}
          onValueChange={([v]) => setPoints(v)}
          className="flex-1"
        />
        <Input
          type="number"
          value={points}
          onChange={(e) => setPoints(Math.min(Number(e.target.value), maxRedeemable))}
          className="w-24"
        />
      </div>

      <div className="flex justify-between items-center mt-4">
        <span className="text-sm text-muted-foreground">
          Discount: {formatCurrency(discount)}
        </span>
        <Button
          onClick={() => onRedeem(points, discount)}
          disabled={points < config.redemption.minPoints}
        >
          Apply
        </Button>
      </div>
    </div>
  );
};
```

## Expiration Job

```typescript
// Background job to expire old points
const expirePoints = async () => {
  const now = new Date();

  // Find all unexpired points that should expire
  const expiringTransactions = await prisma.loyaltyTransaction.findMany({
    where: {
      type: 'EARN',
      expiresAt: { lte: now },
      // Only consider transactions that haven't been offset by expirations
    }
  });

  // Group by customer and calculate expiring amounts
  const customerExpirations = new Map<string, number>();

  for (const tx of expiringTransactions) {
    const current = customerExpirations.get(tx.customerId) || 0;
    customerExpirations.set(tx.customerId, current + tx.points);
  }

  // Create expiration transactions
  for (const [customerId, points] of customerExpirations) {
    const customer = await prisma.customer.findUnique({
      where: { id: customerId }
    });

    const expiringPoints = Math.min(points, customer.loyaltyPoints);
    if (expiringPoints <= 0) continue;

    const newBalance = customer.loyaltyPoints - expiringPoints;

    await prisma.loyaltyTransaction.create({
      data: {
        customerId,
        type: 'EXPIRE',
        points: -expiringPoints,
        balance: newBalance,
        description: 'Points expired'
      }
    });

    await prisma.customer.update({
      where: { id: customerId },
      data: { loyaltyPoints: newBalance }
    });

    // Notify customer
    await sendNotification(customerId, {
      type: 'points_expired',
      title: 'Points Expired',
      body: `${expiringPoints} loyalty points have expired.`
    });
  }
};

// Run daily
cron.schedule('0 1 * * *', expirePoints);
```
