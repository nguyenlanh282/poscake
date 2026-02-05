# Marketing Automation

Tự động hóa marketing campaigns cho CRM.

## Overview

Marketing automation cho phép gửi email, SMS và notifications tự động dựa trên triggers và schedules.

## Campaign Types

```typescript
type CampaignType = 'email' | 'sms' | 'push' | 'multi_channel';
type CampaignStatus = 'draft' | 'scheduled' | 'active' | 'paused' | 'completed';

interface Campaign {
  id: string;
  name: string;
  type: CampaignType;
  status: CampaignStatus;

  // Targeting
  targetSegment?: CustomerSegment;
  targetCustomSegmentId?: string;
  targetTags?: string[];

  // Content
  subject?: string;          // Email subject
  content: string;           // Template content
  templateId?: string;

  // Scheduling
  scheduleType: 'immediate' | 'scheduled' | 'trigger';
  scheduledAt?: Date;
  trigger?: CampaignTrigger;

  // Stats
  sentCount: number;
  openCount: number;
  clickCount: number;
  conversionCount: number;

  createdAt: Date;
  updatedAt: Date;
}

interface CampaignTrigger {
  event: TriggerEvent;
  delay?: string;            // e.g., "1d", "2h", "30m"
  conditions?: TriggerCondition[];
}

type TriggerEvent =
  | 'first_purchase'
  | 'order_completed'
  | 'abandoned_cart'
  | 'no_purchase_days'
  | 'birthday'
  | 'tier_upgrade'
  | 'points_expiring';

interface TriggerCondition {
  field: string;
  operator: string;
  value: any;
}
```

## Email Templates

```typescript
interface EmailTemplate {
  id: string;
  name: string;
  category: TemplateCategory;
  subject: string;
  htmlContent: string;
  textContent?: string;
  variables: string[];        // Available merge tags
}

type TemplateCategory = 'welcome' | 'transactional' | 'promotional' | 'win_back' | 'birthday';

// Available merge tags
const mergeTags = {
  customer: ['{{customer.name}}', '{{customer.email}}', '{{customer.phone}}'],
  order: ['{{order.number}}', '{{order.total}}', '{{order.items}}'],
  loyalty: ['{{points.balance}}', '{{points.expiring}}', '{{tier.name}}'],
  store: ['{{store.name}}', '{{store.address}}', '{{store.phone}}']
};
```

## Trigger-based Automation

```typescript
// services/marketingAutomation.ts

const automations = [
  // Welcome series
  {
    trigger: { event: 'first_purchase' },
    actions: [
      { delay: '0', type: 'email', templateId: 'welcome_email' },
      { delay: '3d', type: 'email', templateId: 'product_tips' },
      { delay: '7d', type: 'email', templateId: 'loyalty_intro' }
    ]
  },

  // Abandoned cart
  {
    trigger: {
      event: 'abandoned_cart',
      conditions: [{ field: 'cartValue', operator: 'gte', value: 200000 }]
    },
    actions: [
      { delay: '1h', type: 'email', templateId: 'cart_reminder' },
      { delay: '24h', type: 'sms', templateId: 'cart_sms' }
    ]
  },

  // Win-back
  {
    trigger: {
      event: 'no_purchase_days',
      conditions: [{ field: 'days', operator: 'gte', value: 30 }]
    },
    actions: [
      { delay: '0', type: 'email', templateId: 'miss_you' },
      { delay: '7d', type: 'email', templateId: 'comeback_offer' }
    ]
  },

  // Birthday
  {
    trigger: { event: 'birthday' },
    actions: [
      { delay: '-1d', type: 'email', templateId: 'birthday_early' },
      { delay: '0', type: 'sms', templateId: 'birthday_sms' }
    ]
  },

  // Points expiring
  {
    trigger: {
      event: 'points_expiring',
      conditions: [{ field: 'daysUntilExpiry', operator: 'lte', value: 7 }]
    },
    actions: [
      { delay: '0', type: 'email', templateId: 'points_expiring' },
      { delay: '3d', type: 'push', templateId: 'points_expiring_push' }
    ]
  }
];

// Process triggers
export const processTrigger = async (
  event: TriggerEvent,
  customerId: string,
  data: Record<string, any>
) => {
  const matchingAutomations = automations.filter(
    a => a.trigger.event === event
  );

  for (const automation of matchingAutomations) {
    // Check conditions
    const conditionsMet = automation.trigger.conditions?.every(
      c => evaluateCondition(c, data)
    ) ?? true;

    if (!conditionsMet) continue;

    // Queue actions
    for (const action of automation.actions) {
      await queueAutomationAction({
        customerId,
        action,
        data,
        executeAt: parseDelay(action.delay)
      });
    }
  }
};

const parseDelay = (delay: string): Date => {
  const now = new Date();
  const match = delay.match(/^(-?)(\d+)([dhm])$/);
  if (!match) return now;

  const [, negative, value, unit] = match;
  const ms = parseInt(value) * {
    'd': 86400000,
    'h': 3600000,
    'm': 60000
  }[unit];

  return new Date(now.getTime() + (negative ? -ms : ms));
};
```

## Email Sending

```typescript
// lib/email.ts
import { Resend } from 'resend';

const resend = new Resend(process.env.RESEND_API_KEY);

export const sendEmail = async (
  to: string,
  template: EmailTemplate,
  data: Record<string, any>
): Promise<{ success: boolean; messageId?: string }> => {
  const subject = replaceMergeTags(template.subject, data);
  const html = replaceMergeTags(template.htmlContent, data);
  const text = template.textContent
    ? replaceMergeTags(template.textContent, data)
    : undefined;

  try {
    const result = await resend.emails.send({
      from: process.env.EMAIL_FROM!,
      to,
      subject,
      html,
      text,
      headers: {
        'X-Campaign-ID': data.campaignId
      }
    });

    return { success: true, messageId: result.id };
  } catch (error) {
    console.error('Email send error:', error);
    return { success: false };
  }
};

const replaceMergeTags = (content: string, data: Record<string, any>): string => {
  return content.replace(/\{\{(\w+)\.(\w+)\}\}/g, (match, obj, prop) => {
    return data[obj]?.[prop] ?? match;
  });
};
```

## SMS Sending

```typescript
// lib/sms.ts
import twilio from 'twilio';

const client = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);

export const sendSMS = async (
  to: string,
  message: string
): Promise<{ success: boolean; messageId?: string }> => {
  try {
    const result = await client.messages.create({
      body: message,
      from: process.env.TWILIO_PHONE_NUMBER,
      to: formatPhoneNumber(to)
    });

    return { success: true, messageId: result.sid };
  } catch (error) {
    console.error('SMS send error:', error);
    return { success: false };
  }
};

const formatPhoneNumber = (phone: string): string => {
  // Convert Vietnamese format to E.164
  if (phone.startsWith('0')) {
    return '+84' + phone.slice(1);
  }
  return phone;
};
```

## Campaign Builder Component

```tsx
const CampaignBuilder = () => {
  const [campaign, setCampaign] = useState<Partial<Campaign>>({
    type: 'email',
    status: 'draft',
    scheduleType: 'immediate'
  });

  const [step, setStep] = useState(1);

  return (
    <div className="space-y-6">
      {/* Steps indicator */}
      <div className="flex items-center justify-between">
        {['Type', 'Audience', 'Content', 'Schedule', 'Review'].map((label, i) => (
          <div
            key={label}
            className={cn(
              "flex items-center gap-2",
              i + 1 === step ? "text-primary" : "text-muted-foreground"
            )}
          >
            <div className={cn(
              "w-8 h-8 rounded-full flex items-center justify-center",
              i + 1 <= step ? "bg-primary text-white" : "bg-muted"
            )}>
              {i + 1}
            </div>
            <span>{label}</span>
          </div>
        ))}
      </div>

      {/* Step content */}
      {step === 1 && <CampaignTypeStep />}
      {step === 2 && <AudienceStep />}
      {step === 3 && <ContentStep />}
      {step === 4 && <ScheduleStep />}
      {step === 5 && <ReviewStep />}

      {/* Navigation */}
      <div className="flex justify-between pt-6 border-t">
        <Button
          variant="outline"
          onClick={() => setStep(s => s - 1)}
          disabled={step === 1}
        >
          Back
        </Button>
        <Button onClick={() => step < 5 ? setStep(s => s + 1) : saveCampaign()}>
          {step < 5 ? 'Next' : 'Launch Campaign'}
        </Button>
      </div>
    </div>
  );
};
```

## A/B Testing

```typescript
interface ABTest {
  id: string;
  campaignId: string;
  variants: ABVariant[];
  winningCriteria: 'open_rate' | 'click_rate' | 'conversion_rate';
  testDuration: number;        // Hours
  sampleSize: number;          // Percentage of audience
  status: 'running' | 'completed';
  winner?: string;
}

interface ABVariant {
  id: string;
  name: string;               // e.g., "Variant A"
  subject?: string;           // For email
  content: string;
  sentCount: number;
  opens: number;
  clicks: number;
  conversions: number;
}

export const runABTest = async (test: ABTest) => {
  const audience = await getAudienceForCampaign(test.campaignId);
  const sampleCount = Math.floor(audience.length * test.sampleSize / 100);

  // Split sample into variants
  const shuffled = shuffleArray(audience.slice(0, sampleCount));
  const variantSize = Math.floor(sampleCount / test.variants.length);

  for (let i = 0; i < test.variants.length; i++) {
    const variantAudience = shuffled.slice(i * variantSize, (i + 1) * variantSize);

    for (const customer of variantAudience) {
      await sendCampaignMessage(test.campaignId, customer.id, test.variants[i]);
    }
  }

  // Schedule winner selection
  setTimeout(() => selectWinner(test.id), test.testDuration * 3600000);
};

const selectWinner = async (testId: string) => {
  const test = await prisma.abTest.findUnique({
    where: { id: testId },
    include: { variants: true }
  });

  const getMetric = (v: ABVariant) => {
    switch (test.winningCriteria) {
      case 'open_rate': return v.opens / v.sentCount;
      case 'click_rate': return v.clicks / v.sentCount;
      case 'conversion_rate': return v.conversions / v.sentCount;
    }
  };

  const winner = test.variants.reduce((best, v) =>
    getMetric(v) > getMetric(best) ? v : best
  );

  await prisma.abTest.update({
    where: { id: testId },
    data: { status: 'completed', winner: winner.id }
  });

  // Send winner to remaining audience
  const remainingAudience = await getRemainingAudience(test.campaignId);
  for (const customer of remainingAudience) {
    await sendCampaignMessage(test.campaignId, customer.id, winner);
  }
};
```

## Campaign Analytics

```typescript
interface CampaignAnalytics {
  sent: number;
  delivered: number;
  opened: number;
  clicked: number;
  converted: number;
  unsubscribed: number;
  bounced: number;

  openRate: number;
  clickRate: number;
  conversionRate: number;
  deliveryRate: number;
}

export const getCampaignAnalytics = async (campaignId: string): Promise<CampaignAnalytics> => {
  const stats = await prisma.campaignMessage.groupBy({
    by: ['status'],
    where: { campaignId },
    _count: true
  });

  const sent = stats.find(s => s.status === 'sent')?._count || 0;
  const delivered = stats.find(s => s.status === 'delivered')?._count || 0;
  const opened = stats.find(s => s.status === 'opened')?._count || 0;
  const clicked = stats.find(s => s.status === 'clicked')?._count || 0;
  const converted = stats.find(s => s.status === 'converted')?._count || 0;
  const unsubscribed = stats.find(s => s.status === 'unsubscribed')?._count || 0;
  const bounced = stats.find(s => s.status === 'bounced')?._count || 0;

  return {
    sent,
    delivered,
    opened,
    clicked,
    converted,
    unsubscribed,
    bounced,
    openRate: (opened / delivered) * 100,
    clickRate: (clicked / opened) * 100,
    conversionRate: (converted / clicked) * 100,
    deliveryRate: (delivered / sent) * 100
  };
};
```
