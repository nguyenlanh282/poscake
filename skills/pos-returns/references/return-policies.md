# Return Policies

Cấu hình chính sách đổi trả hàng.

## Overview

Return policies định nghĩa các quy tắc về thời hạn, điều kiện, và loại sản phẩm được phép đổi trả.

## Policy Configuration

```typescript
interface ReturnPolicy {
  id: string;
  name: string;
  isDefault: boolean;
  status: 'active' | 'inactive';

  // Time limits
  returnWindowDays: number;    // Days after purchase
  exchangeWindowDays: number;  // May be longer

  // Conditions
  requireReceipt: boolean;
  requireOriginalPackaging: boolean;
  requireTags: boolean;
  requireUnused: boolean;

  // Fees
  restockingFee: RestockingFee | null;

  // Exclusions
  excludedCategories: string[];
  excludedProducts: string[];

  // Special rules
  rules: PolicyRule[];

  createdAt: Date;
  updatedAt: Date;
}

interface RestockingFee {
  type: 'percentage' | 'fixed';
  value: number;
  exemptReasons: ReturnReason[];
}

interface PolicyRule {
  id: string;
  name: string;
  condition: RuleCondition;
  action: RuleAction;
  priority: number;
}

interface RuleCondition {
  field: 'category' | 'price' | 'daysElapsed' | 'customerTier' | 'reason';
  operator: 'eq' | 'neq' | 'gt' | 'gte' | 'lt' | 'lte' | 'in';
  value: any;
}

interface RuleAction {
  type: 'allow' | 'deny' | 'require_approval' | 'apply_fee' | 'limit_refund_method';
  value?: any;
}

// Default policy
const defaultReturnPolicy: ReturnPolicy = {
  id: 'default',
  name: 'Standard Return Policy',
  isDefault: true,
  status: 'active',

  returnWindowDays: 30,
  exchangeWindowDays: 60,

  requireReceipt: true,
  requireOriginalPackaging: false,
  requireTags: true,
  requireUnused: false,

  restockingFee: {
    type: 'percentage',
    value: 15,
    exemptReasons: ['defective', 'wrong_item', 'damaged_shipping']
  },

  excludedCategories: [
    'food',
    'personal_care',
    'underwear',
    'swimwear',
    'earrings',
    'clearance'
  ],

  excludedProducts: [],

  rules: [
    {
      id: 'vip_extended',
      name: 'VIP Extended Return Window',
      condition: { field: 'customerTier', operator: 'in', value: ['gold', 'platinum'] },
      action: { type: 'allow', value: { returnWindowDays: 60 } },
      priority: 10
    },
    {
      id: 'high_value_approval',
      name: 'High Value Requires Approval',
      condition: { field: 'price', operator: 'gte', value: 5000000 },
      action: { type: 'require_approval' },
      priority: 20
    },
    {
      id: 'electronics_restocking',
      name: 'Electronics Restocking Fee',
      condition: { field: 'category', operator: 'eq', value: 'electronics' },
      action: { type: 'apply_fee', value: { percentage: 20 } },
      priority: 30
    }
  ],

  createdAt: new Date(),
  updatedAt: new Date()
};
```

## Policy Evaluation

```typescript
// services/returnPolicy.ts

interface PolicyEvaluation {
  allowed: boolean;
  reason?: string;
  requiresApproval: boolean;
  restockingFee: number;
  refundMethods: RefundMethod[];
  warnings: string[];
}

export const evaluateReturnEligibility = async (
  orderId: string,
  items: { productId: string; quantity: number }[],
  reason: ReturnReason
): Promise<PolicyEvaluation> => {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: {
      customer: { include: { loyalty: true } },
      items: { include: { product: { include: { category: true } } } }
    }
  });

  const policy = await getActivePolicy();
  const daysSincePurchase = differenceInDays(new Date(), order.createdAt);

  const evaluation: PolicyEvaluation = {
    allowed: true,
    requiresApproval: false,
    restockingFee: 0,
    refundMethods: ['original_payment', 'store_credit'],
    warnings: []
  };

  // Check time window
  const effectiveWindow = getEffectiveWindow(policy, order.customer);
  if (daysSincePurchase > effectiveWindow) {
    return {
      ...evaluation,
      allowed: false,
      reason: `Return window expired (${policy.returnWindowDays} days)`
    };
  }

  // Check each item
  for (const item of items) {
    const orderItem = order.items.find(i => i.productId === item.productId);
    const product = orderItem.product;

    // Check excluded categories
    if (policy.excludedCategories.includes(product.category.slug)) {
      return {
        ...evaluation,
        allowed: false,
        reason: `${product.category.name} items cannot be returned`
      };
    }

    // Check excluded products
    if (policy.excludedProducts.includes(product.id)) {
      return {
        ...evaluation,
        allowed: false,
        reason: `${product.name} is not eligible for return`
      };
    }
  }

  // Apply policy rules
  for (const rule of policy.rules.sort((a, b) => a.priority - b.priority)) {
    if (evaluateCondition(rule.condition, { order, items, reason })) {
      applyAction(rule.action, evaluation);
    }
  }

  // Calculate restocking fee
  if (policy.restockingFee && !policy.restockingFee.exemptReasons.includes(reason)) {
    const itemsTotal = items.reduce((sum, item) => {
      const orderItem = order.items.find(i => i.productId === item.productId);
      return sum + orderItem.unitPrice * item.quantity;
    }, 0);

    evaluation.restockingFee = policy.restockingFee.type === 'percentage'
      ? itemsTotal * (policy.restockingFee.value / 100)
      : policy.restockingFee.value;
  }

  // Warnings
  if (!order.hasReceipt && policy.requireReceipt) {
    evaluation.warnings.push('Receipt required - customer must provide proof of purchase');
  }

  if (daysSincePurchase > effectiveWindow - 7) {
    evaluation.warnings.push('Approaching return deadline');
  }

  return evaluation;
};

const getEffectiveWindow = (policy: ReturnPolicy, customer: Customer): number => {
  // Check for VIP extended window
  const vipTiers = ['gold', 'platinum'];
  if (vipTiers.includes(customer.loyalty?.tier)) {
    const vipRule = policy.rules.find(r =>
      r.condition.field === 'customerTier' &&
      r.action.value?.returnWindowDays
    );
    if (vipRule) return vipRule.action.value.returnWindowDays;
  }
  return policy.returnWindowDays;
};
```

## Components

### ReturnPolicyEditor

```tsx
const ReturnPolicyEditor = ({ policy, onSave }: ReturnPolicyEditorProps) => {
  const form = useForm<ReturnPolicy>({ defaultValues: policy });

  return (
    <form onSubmit={form.handleSubmit(onSave)} className="space-y-6">
      {/* Basic Info */}
      <Card>
        <CardHeader>
          <CardTitle>Basic Information</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label>Policy Name</Label>
            <Input {...form.register('name')} />
          </div>
          <div className="flex items-center gap-2">
            <Switch {...form.register('isDefault')} />
            <Label>Set as default policy</Label>
          </div>
        </CardContent>
      </Card>

      {/* Time Limits */}
      <Card>
        <CardHeader>
          <CardTitle>Time Limits</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-4">
          <div>
            <Label>Return Window (days)</Label>
            <Input
              type="number"
              {...form.register('returnWindowDays', { valueAsNumber: true })}
            />
          </div>
          <div>
            <Label>Exchange Window (days)</Label>
            <Input
              type="number"
              {...form.register('exchangeWindowDays', { valueAsNumber: true })}
            />
          </div>
        </CardContent>
      </Card>

      {/* Conditions */}
      <Card>
        <CardHeader>
          <CardTitle>Return Conditions</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center justify-between">
            <Label>Require receipt/proof of purchase</Label>
            <Switch {...form.register('requireReceipt')} />
          </div>
          <div className="flex items-center justify-between">
            <Label>Require original packaging</Label>
            <Switch {...form.register('requireOriginalPackaging')} />
          </div>
          <div className="flex items-center justify-between">
            <Label>Require tags attached</Label>
            <Switch {...form.register('requireTags')} />
          </div>
          <div className="flex items-center justify-between">
            <Label>Require unused/unworn condition</Label>
            <Switch {...form.register('requireUnused')} />
          </div>
        </CardContent>
      </Card>

      {/* Restocking Fee */}
      <Card>
        <CardHeader>
          <CardTitle>Restocking Fee</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center gap-4">
            <Select {...form.register('restockingFee.type')}>
              <SelectItem value="percentage">Percentage</SelectItem>
              <SelectItem value="fixed">Fixed Amount</SelectItem>
            </Select>
            <Input
              type="number"
              {...form.register('restockingFee.value', { valueAsNumber: true })}
              className="w-32"
            />
          </div>
          <div>
            <Label>Exempt for these reasons:</Label>
            <div className="flex flex-wrap gap-2 mt-2">
              {returnReasons.map(reason => (
                <label key={reason.value} className="flex items-center gap-1">
                  <Checkbox
                    checked={form.watch('restockingFee.exemptReasons')?.includes(reason.value)}
                    onCheckedChange={(checked) => {
                      const current = form.getValues('restockingFee.exemptReasons') || [];
                      form.setValue('restockingFee.exemptReasons',
                        checked
                          ? [...current, reason.value]
                          : current.filter(r => r !== reason.value)
                      );
                    }}
                  />
                  {reason.label}
                </label>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Excluded Categories */}
      <Card>
        <CardHeader>
          <CardTitle>Excluded Categories</CardTitle>
        </CardHeader>
        <CardContent>
          <CategorySelector
            selected={form.watch('excludedCategories')}
            onChange={(cats) => form.setValue('excludedCategories', cats)}
          />
        </CardContent>
      </Card>

      <Button type="submit" className="w-full">Save Policy</Button>
    </form>
  );
};
```

### PolicyDisplay

```tsx
const PolicyDisplay = ({ policy }: { policy: ReturnPolicy }) => (
  <div className="prose prose-sm max-w-none">
    <h3>Return Policy</h3>

    <h4>Time Limits</h4>
    <ul>
      <li>Returns accepted within <strong>{policy.returnWindowDays} days</strong> of purchase</li>
      <li>Exchanges accepted within <strong>{policy.exchangeWindowDays} days</strong> of purchase</li>
    </ul>

    <h4>Conditions</h4>
    <ul>
      {policy.requireReceipt && <li>Original receipt or proof of purchase required</li>}
      {policy.requireOriginalPackaging && <li>Items must be in original packaging</li>}
      {policy.requireTags && <li>All tags must be attached</li>}
      {policy.requireUnused && <li>Items must be unused/unworn</li>}
    </ul>

    {policy.restockingFee && (
      <>
        <h4>Restocking Fee</h4>
        <p>
          A {policy.restockingFee.type === 'percentage'
            ? `${policy.restockingFee.value}%`
            : formatCurrency(policy.restockingFee.value)
          } restocking fee applies, except for:
        </p>
        <ul>
          {policy.restockingFee.exemptReasons.map(reason => (
            <li key={reason}>{getReasonLabel(reason)}</li>
          ))}
        </ul>
      </>
    )}

    {policy.excludedCategories.length > 0 && (
      <>
        <h4>Non-Returnable Items</h4>
        <p>The following categories cannot be returned:</p>
        <ul>
          {policy.excludedCategories.map(cat => (
            <li key={cat}>{getCategoryName(cat)}</li>
          ))}
        </ul>
      </>
    )}
  </div>
);
```

## Return Reasons

```typescript
const returnReasons = [
  { value: 'defective', label: 'Defective/Damaged Product', requiresEvidence: true },
  { value: 'wrong_item', label: 'Wrong Item Received', requiresEvidence: true },
  { value: 'not_as_described', label: 'Not as Described', requiresEvidence: false },
  { value: 'changed_mind', label: 'Changed Mind', requiresEvidence: false },
  { value: 'damaged_shipping', label: 'Damaged in Shipping', requiresEvidence: true },
  { value: 'size_issue', label: 'Size/Fit Issue', requiresEvidence: false },
  { value: 'quality_issue', label: 'Quality Issue', requiresEvidence: false },
  { value: 'other', label: 'Other', requiresEvidence: false }
];

// Reason-specific handling
const reasonHandling: Record<ReturnReason, ReasonHandler> = {
  defective: {
    autoApprove: false,
    requiresInspection: true,
    refundShipping: true,
    freeReturnShipping: true
  },
  wrong_item: {
    autoApprove: true,
    requiresInspection: false,
    refundShipping: true,
    freeReturnShipping: true
  },
  changed_mind: {
    autoApprove: true,
    requiresInspection: false,
    refundShipping: false,
    freeReturnShipping: false
  }
  // ... etc
};
```
