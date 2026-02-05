# Credit Risk Management

Đánh giá và quản lý rủi ro tín dụng khách hàng.

## Overview

Credit risk management giúp đánh giá khả năng thanh toán của khách hàng, đề xuất hạn mức tín dụng phù hợp, và cảnh báo rủi ro.

## Credit Scoring

```typescript
interface CreditScore {
  customerId: string;
  score: number;              // 0-100
  grade: CreditGrade;
  factors: CreditFactor[];
  recommendation: CreditRecommendation;
  calculatedAt: Date;
}

type CreditGrade = 'A' | 'B' | 'C' | 'D' | 'F';

interface CreditFactor {
  name: string;
  weight: number;             // Percentage
  score: number;              // 0-100
  impact: 'positive' | 'neutral' | 'negative';
  description: string;
}

interface CreditRecommendation {
  action: 'approve' | 'approve_with_conditions' | 'review' | 'decline';
  suggestedLimit?: number;
  suggestedTerms?: number;
  conditions?: string[];
  reason: string;
}

// Scoring factors and weights
const scoringModel = {
  paymentHistory: {
    weight: 35,
    calculate: (customer: Customer) => {
      const onTimeRate = customer.credit.onTimePaymentRate;
      return onTimeRate; // 0-100
    }
  },
  creditUtilization: {
    weight: 20,
    calculate: (customer: Customer) => {
      const utilization = customer.credit.totalOutstanding / customer.credit.creditLimit;
      // Lower utilization = higher score
      if (utilization < 0.3) return 100;
      if (utilization < 0.5) return 80;
      if (utilization < 0.7) return 60;
      if (utilization < 0.9) return 40;
      return 20;
    }
  },
  accountAge: {
    weight: 15,
    calculate: (customer: Customer) => {
      const months = differenceInMonths(new Date(), customer.createdAt);
      if (months >= 24) return 100;
      if (months >= 12) return 80;
      if (months >= 6) return 60;
      if (months >= 3) return 40;
      return 20;
    }
  },
  orderHistory: {
    weight: 15,
    calculate: (customer: Customer) => {
      const avgOrderValue = customer.lifetimeValue / customer.orderCount;
      const orderFrequency = customer.orderCount / differenceInMonths(new Date(), customer.firstOrderAt);
      // Combine AOV and frequency
      return Math.min(100, (avgOrderValue / 1000000 + orderFrequency) * 10);
    }
  },
  currentOverdue: {
    weight: 15,
    calculate: (customer: Customer) => {
      const overdueRatio = customer.credit.overdueAmount / customer.credit.totalOutstanding;
      if (overdueRatio === 0) return 100;
      if (overdueRatio < 0.1) return 70;
      if (overdueRatio < 0.3) return 40;
      return 0;
    }
  }
};
```

## Service Implementation

```typescript
// services/creditRisk.ts

export const calculateCreditScore = async (customerId: string): Promise<CreditScore> => {
  const customer = await prisma.customer.findUnique({
    where: { id: customerId },
    include: {
      credit: true,
      orders: true,
      invoices: {
        where: { status: { in: ['PAID', 'OVERDUE'] } }
      }
    }
  });

  const factors: CreditFactor[] = [];
  let totalScore = 0;

  for (const [factorName, config] of Object.entries(scoringModel)) {
    const score = config.calculate(customer);
    const weightedScore = score * (config.weight / 100);
    totalScore += weightedScore;

    factors.push({
      name: factorName,
      weight: config.weight,
      score,
      impact: score >= 70 ? 'positive' : score >= 40 ? 'neutral' : 'negative',
      description: getFactorDescription(factorName, score)
    });
  }

  const grade = getGrade(totalScore);
  const recommendation = generateRecommendation(totalScore, factors, customer);

  const creditScore = await prisma.creditScore.create({
    data: {
      customerId,
      score: totalScore,
      grade,
      factors,
      recommendation,
      calculatedAt: new Date()
    }
  });

  return creditScore;
};

const getGrade = (score: number): CreditGrade => {
  if (score >= 80) return 'A';
  if (score >= 65) return 'B';
  if (score >= 50) return 'C';
  if (score >= 35) return 'D';
  return 'F';
};

const generateRecommendation = (
  score: number,
  factors: CreditFactor[],
  customer: Customer
): CreditRecommendation => {
  const currentLimit = customer.credit?.creditLimit || 0;
  const hasOverdue = factors.find(f => f.name === 'currentOverdue')?.score < 50;

  if (score >= 80) {
    return {
      action: 'approve',
      suggestedLimit: Math.min(currentLimit * 1.5, 100000000),
      suggestedTerms: 60,
      reason: 'Excellent credit profile with strong payment history'
    };
  }

  if (score >= 65) {
    return {
      action: 'approve',
      suggestedLimit: currentLimit * 1.2,
      suggestedTerms: 45,
      reason: 'Good credit profile'
    };
  }

  if (score >= 50) {
    return {
      action: 'approve_with_conditions',
      suggestedLimit: currentLimit,
      suggestedTerms: 30,
      conditions: hasOverdue
        ? ['Clear overdue balance before new credit']
        : ['Shorter payment terms'],
      reason: 'Fair credit profile, standard terms apply'
    };
  }

  if (score >= 35) {
    return {
      action: 'review',
      suggestedLimit: currentLimit * 0.5,
      suggestedTerms: 15,
      conditions: ['Require deposit', 'Review quarterly'],
      reason: 'Below average credit profile, manual review required'
    };
  }

  return {
    action: 'decline',
    reason: 'Poor credit profile due to payment history'
  };
};
```

## Risk Alerts

```typescript
interface RiskAlert {
  id: string;
  customerId: string;
  type: RiskAlertType;
  severity: 'low' | 'medium' | 'high' | 'critical';
  message: string;
  data: Record<string, any>;
  createdAt: Date;
  acknowledgedAt?: Date;
  acknowledgedBy?: string;
}

type RiskAlertType =
  | 'score_drop'
  | 'overdue_increase'
  | 'credit_limit_breach'
  | 'payment_pattern_change'
  | 'high_utilization'
  | 'multiple_late_payments';

// Monitor and create alerts
export const monitorCreditRisks = async () => {
  const customersWithCredit = await prisma.customerCredit.findMany({
    where: { status: 'ACTIVE' },
    include: {
      customer: true,
      recentScores: {
        orderBy: { calculatedAt: 'desc' },
        take: 2
      }
    }
  });

  for (const credit of customersWithCredit) {
    const alerts: Partial<RiskAlert>[] = [];

    // Check score drop
    if (credit.recentScores.length >= 2) {
      const [current, previous] = credit.recentScores;
      const drop = previous.score - current.score;
      if (drop >= 20) {
        alerts.push({
          type: 'score_drop',
          severity: drop >= 30 ? 'high' : 'medium',
          message: `Credit score dropped by ${drop} points`,
          data: { previousScore: previous.score, currentScore: current.score }
        });
      }
    }

    // Check high utilization
    const utilization = Number(credit.totalOutstanding) / Number(credit.creditLimit);
    if (utilization >= 0.9) {
      alerts.push({
        type: 'high_utilization',
        severity: 'medium',
        message: `Credit utilization at ${(utilization * 100).toFixed(0)}%`,
        data: { utilization, outstanding: credit.totalOutstanding, limit: credit.creditLimit }
      });
    }

    // Check overdue amount increase
    if (Number(credit.overdueAmount) > 0) {
      const overdueRatio = Number(credit.overdueAmount) / Number(credit.totalOutstanding);
      alerts.push({
        type: 'overdue_increase',
        severity: overdueRatio >= 0.5 ? 'critical' : overdueRatio >= 0.3 ? 'high' : 'medium',
        message: `${(overdueRatio * 100).toFixed(0)}% of outstanding is overdue`,
        data: { overdueAmount: credit.overdueAmount, overdueRatio }
      });
    }

    // Create alerts
    for (const alert of alerts) {
      await prisma.riskAlert.create({
        data: {
          customerId: credit.customerId,
          ...alert
        }
      });
    }
  }
};

// Run daily
cron.schedule('0 8 * * *', monitorCreditRisks);
```

## Credit Limit Recommendations

```typescript
interface LimitRecommendation {
  customerId: string;
  currentLimit: number;
  recommendedLimit: number;
  change: number;
  changePercent: number;
  reason: string;
  factors: {
    paymentBehavior: 'excellent' | 'good' | 'fair' | 'poor';
    utilizationPattern: string;
    orderTrend: 'increasing' | 'stable' | 'decreasing';
  };
}

export const recommendCreditLimits = async (): Promise<LimitRecommendation[]> => {
  const customers = await prisma.customerCredit.findMany({
    where: { status: 'ACTIVE' },
    include: {
      customer: {
        include: {
          orders: {
            where: { createdAt: { gte: subMonths(new Date(), 6) } }
          }
        }
      },
      creditScores: {
        orderBy: { calculatedAt: 'desc' },
        take: 1
      }
    }
  });

  const recommendations: LimitRecommendation[] = [];

  for (const credit of customers) {
    const score = credit.creditScores[0]?.score || 50;
    const avgUtilization = calculateAvgUtilization(credit);
    const orderTrend = calculateOrderTrend(credit.customer.orders);

    let recommendedLimit = Number(credit.creditLimit);
    let reason = '';

    // High performers - increase limit
    if (score >= 80 && avgUtilization >= 0.7) {
      recommendedLimit *= 1.5;
      reason = 'Excellent payment history with high utilization - ready for increase';
    }
    // Good performers
    else if (score >= 65 && avgUtilization >= 0.5) {
      recommendedLimit *= 1.2;
      reason = 'Good payment behavior with consistent usage';
    }
    // Underutilized
    else if (avgUtilization < 0.2 && score >= 50) {
      // Don't change, but note it
      reason = 'Credit underutilized - monitor for activity';
    }
    // Risky - consider decrease
    else if (score < 40) {
      recommendedLimit *= 0.7;
      reason = 'Payment issues - recommend reducing exposure';
    }

    const change = recommendedLimit - Number(credit.creditLimit);
    if (Math.abs(change) > 0) {
      recommendations.push({
        customerId: credit.customerId,
        currentLimit: Number(credit.creditLimit),
        recommendedLimit,
        change,
        changePercent: (change / Number(credit.creditLimit)) * 100,
        reason,
        factors: {
          paymentBehavior: getPaymentBehaviorLabel(score),
          utilizationPattern: `${(avgUtilization * 100).toFixed(0)}% avg utilization`,
          orderTrend
        }
      });
    }
  }

  return recommendations.sort((a, b) => b.changePercent - a.changePercent);
};
```

## Components

### CreditScoreCard

```tsx
const CreditScoreCard = ({ score }: { score: CreditScore }) => {
  const gradeColors = {
    A: 'text-green-600 bg-green-100',
    B: 'text-blue-600 bg-blue-100',
    C: 'text-yellow-600 bg-yellow-100',
    D: 'text-orange-600 bg-orange-100',
    F: 'text-red-600 bg-red-100'
  };

  return (
    <Card>
      <CardContent className="p-6">
        <div className="flex items-center gap-6">
          {/* Score gauge */}
          <div className="relative w-32 h-32">
            <svg className="w-full h-full" viewBox="0 0 100 100">
              <circle
                cx="50" cy="50" r="45"
                fill="none" stroke="#e5e7eb" strokeWidth="10"
              />
              <circle
                cx="50" cy="50" r="45"
                fill="none"
                stroke={getScoreColor(score.score)}
                strokeWidth="10"
                strokeDasharray={`${score.score * 2.83} 283`}
                transform="rotate(-90 50 50)"
              />
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <span className="text-3xl font-bold">{score.score}</span>
              <span className={cn(
                "text-lg font-semibold px-2 rounded",
                gradeColors[score.grade]
              )}>
                Grade {score.grade}
              </span>
            </div>
          </div>

          {/* Factors */}
          <div className="flex-1 space-y-2">
            {score.factors.map(factor => (
              <div key={factor.name} className="flex items-center gap-2">
                <div className="w-24 text-sm">{factor.name}</div>
                <Progress
                  value={factor.score}
                  className="flex-1 h-2"
                />
                <span className={cn(
                  "text-xs",
                  factor.impact === 'positive' ? 'text-green-600' :
                  factor.impact === 'negative' ? 'text-red-600' :
                  'text-gray-500'
                )}>
                  {factor.score}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Recommendation */}
        <div className={cn(
          "mt-4 p-3 rounded",
          score.recommendation.action === 'approve' ? 'bg-green-50' :
          score.recommendation.action === 'decline' ? 'bg-red-50' :
          'bg-yellow-50'
        )}>
          <p className="font-medium">
            {score.recommendation.action === 'approve' && 'Approved'}
            {score.recommendation.action === 'approve_with_conditions' && 'Approved with Conditions'}
            {score.recommendation.action === 'review' && 'Manual Review Required'}
            {score.recommendation.action === 'decline' && 'Not Recommended'}
          </p>
          <p className="text-sm text-muted-foreground">{score.recommendation.reason}</p>
          {score.recommendation.suggestedLimit && (
            <p className="text-sm mt-1">
              Suggested limit: {formatCurrency(score.recommendation.suggestedLimit)}
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
```

### RiskAlertsList

```tsx
const RiskAlertsList = () => {
  const { data: alerts } = useQuery({
    queryKey: ['risk-alerts'],
    queryFn: () => fetch('/api/debt/risk-alerts?unacknowledged=true').then(r => r.json())
  });

  const severityStyles = {
    critical: 'border-red-500 bg-red-50',
    high: 'border-orange-500 bg-orange-50',
    medium: 'border-yellow-500 bg-yellow-50',
    low: 'border-blue-500 bg-blue-50'
  };

  return (
    <div className="space-y-2">
      {alerts?.map((alert: RiskAlert) => (
        <div
          key={alert.id}
          className={cn(
            "p-3 border-l-4 rounded flex justify-between items-center",
            severityStyles[alert.severity]
          )}
        >
          <div>
            <p className="font-medium">{alert.message}</p>
            <p className="text-sm text-muted-foreground">
              {alert.customerName} • {formatRelativeDate(alert.createdAt)}
            </p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => viewCustomer(alert.customerId)}>
              View
            </Button>
            <Button variant="ghost" size="sm" onClick={() => acknowledgeAlert(alert.id)}>
              <Check className="h-4 w-4" />
            </Button>
          </div>
        </div>
      ))}
    </div>
  );
};
```
