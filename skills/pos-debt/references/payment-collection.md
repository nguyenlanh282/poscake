# Payment Collection

Thu hồi công nợ với reminders và payment plans.

## Overview

Payment collection workflow giúp thu hồi nợ hiệu quả qua reminders tự động, phone calls, và payment plans.

## Collection Workflow

```typescript
interface CollectionWorkflow {
  stages: CollectionStage[];
  escalationRules: EscalationRule[];
}

interface CollectionStage {
  id: string;
  name: string;
  daysOverdue: number;        // Trigger at X days overdue
  actions: CollectionAction[];
  autoEscalate: boolean;
}

interface CollectionAction {
  type: 'email' | 'sms' | 'phone_call' | 'letter' | 'legal_notice';
  templateId: string;
  assignTo?: string;          // Role or user ID
  dueInHours: number;
}

interface EscalationRule {
  fromStage: string;
  toStage: string;
  condition: 'no_response' | 'payment_promise_broken' | 'time_elapsed';
  value?: number;             // Days or amount
}

// Default workflow
const defaultCollectionWorkflow: CollectionWorkflow = {
  stages: [
    {
      id: 'friendly_reminder',
      name: 'Friendly Reminder',
      daysOverdue: 1,
      actions: [
        { type: 'email', templateId: 'payment_due_reminder', dueInHours: 24 }
      ],
      autoEscalate: true
    },
    {
      id: 'first_follow_up',
      name: 'First Follow-up',
      daysOverdue: 7,
      actions: [
        { type: 'sms', templateId: 'payment_overdue_sms', dueInHours: 1 },
        { type: 'email', templateId: 'payment_overdue_email', dueInHours: 24 }
      ],
      autoEscalate: true
    },
    {
      id: 'phone_collection',
      name: 'Phone Collection',
      daysOverdue: 14,
      actions: [
        { type: 'phone_call', templateId: 'collection_call_script', assignTo: 'collections_team', dueInHours: 48 }
      ],
      autoEscalate: true
    },
    {
      id: 'formal_notice',
      name: 'Formal Notice',
      daysOverdue: 30,
      actions: [
        { type: 'letter', templateId: 'formal_collection_notice', dueInHours: 72 },
        { type: 'email', templateId: 'formal_notice_email', dueInHours: 24 }
      ],
      autoEscalate: true
    },
    {
      id: 'final_notice',
      name: 'Final Notice',
      daysOverdue: 45,
      actions: [
        { type: 'legal_notice', templateId: 'final_demand_letter', dueInHours: 72 }
      ],
      autoEscalate: false
    },
    {
      id: 'legal_action',
      name: 'Legal Action',
      daysOverdue: 60,
      actions: [
        { type: 'phone_call', templateId: 'legal_escalation', assignTo: 'legal_team', dueInHours: 24 }
      ],
      autoEscalate: false
    }
  ],
  escalationRules: [
    { fromStage: 'friendly_reminder', toStage: 'first_follow_up', condition: 'time_elapsed', value: 7 },
    { fromStage: 'first_follow_up', toStage: 'phone_collection', condition: 'no_response' },
    { fromStage: 'phone_collection', toStage: 'formal_notice', condition: 'payment_promise_broken' }
  ]
};
```

## Collection Activity

```typescript
interface CollectionActivity {
  id: string;
  invoiceId: string;
  type: CollectionActivityType;
  stage: string;

  // Activity details
  contactMethod: 'email' | 'sms' | 'phone' | 'letter' | 'in_person';
  contactedBy: string;
  contactDate: Date;
  notes: string;

  // Outcome
  outcome: CollectionOutcome;
  promisedAmount?: number;
  promisedDate?: Date;
  nextAction?: string;
  nextActionDate?: Date;
}

type CollectionActivityType = 'reminder_sent' | 'phone_call' | 'email_sent' | 'letter_sent' | 'visit' | 'payment_received' | 'promise_made' | 'dispute_raised';

type CollectionOutcome = 'no_answer' | 'left_message' | 'spoke_to_customer' | 'payment_promised' | 'payment_received' | 'dispute' | 'refused_to_pay' | 'wrong_contact';
```

## Service Implementation

```typescript
// services/paymentCollection.ts

// Process daily collection tasks
export const processDailyCollections = async () => {
  const overdueInvoices = await prisma.invoice.findMany({
    where: {
      status: { in: ['SENT', 'PARTIAL', 'OVERDUE'] },
      balance: { gt: 0 },
      dueDate: { lt: new Date() }
    },
    include: {
      customer: true,
      collectionActivities: {
        orderBy: { contactDate: 'desc' },
        take: 1
      }
    }
  });

  const workflow = await getCollectionWorkflow();

  for (const invoice of overdueInvoices) {
    const daysOverdue = differenceInDays(new Date(), invoice.dueDate);
    const currentStage = getCurrentStage(invoice, workflow);
    const nextStage = getNextStage(currentStage, daysOverdue, workflow);

    if (nextStage && nextStage.id !== currentStage?.id) {
      await executeCollectionStage(invoice, nextStage);
    }
  }
};

const getCurrentStage = (invoice: Invoice, workflow: CollectionWorkflow) => {
  const lastActivity = invoice.collectionActivities[0];
  if (!lastActivity) return null;
  return workflow.stages.find(s => s.id === lastActivity.stage);
};

const getNextStage = (
  currentStage: CollectionStage | null,
  daysOverdue: number,
  workflow: CollectionWorkflow
) => {
  const applicableStages = workflow.stages.filter(s => daysOverdue >= s.daysOverdue);

  if (!currentStage) {
    return applicableStages[0];
  }

  const currentIndex = workflow.stages.findIndex(s => s.id === currentStage.id);
  const nextIndex = currentIndex + 1;

  if (nextIndex < workflow.stages.length && daysOverdue >= workflow.stages[nextIndex].daysOverdue) {
    return workflow.stages[nextIndex];
  }

  return currentStage;
};

const executeCollectionStage = async (invoice: Invoice, stage: CollectionStage) => {
  for (const action of stage.actions) {
    switch (action.type) {
      case 'email':
        await sendCollectionEmail(invoice, action.templateId);
        break;
      case 'sms':
        await sendCollectionSMS(invoice, action.templateId);
        break;
      case 'phone_call':
        await createCollectionTask(invoice, action);
        break;
      case 'letter':
        await generateCollectionLetter(invoice, action.templateId);
        break;
    }
  }

  await prisma.collectionActivity.create({
    data: {
      invoiceId: invoice.id,
      type: 'reminder_sent',
      stage: stage.id,
      contactMethod: action.type === 'phone_call' ? 'phone' : action.type,
      contactedBy: 'system',
      contactDate: new Date(),
      notes: `Automated ${stage.name} action`,
      outcome: 'no_answer'
    }
  });
};

// Record manual collection activity
export const recordCollectionActivity = async (
  invoiceId: string,
  activity: {
    contactMethod: CollectionActivity['contactMethod'];
    notes: string;
    outcome: CollectionOutcome;
    promisedAmount?: number;
    promisedDate?: Date;
  },
  userId: string
) => {
  const invoice = await prisma.invoice.findUnique({
    where: { id: invoiceId }
  });

  const workflow = await getCollectionWorkflow();
  const daysOverdue = differenceInDays(new Date(), invoice.dueDate);
  const currentStage = workflow.stages.find(s => daysOverdue >= s.daysOverdue);

  await prisma.collectionActivity.create({
    data: {
      invoiceId,
      type: activity.outcome === 'payment_promised' ? 'promise_made' : 'phone_call',
      stage: currentStage?.id || 'manual',
      contactMethod: activity.contactMethod,
      contactedBy: userId,
      contactDate: new Date(),
      notes: activity.notes,
      outcome: activity.outcome,
      promisedAmount: activity.promisedAmount,
      promisedDate: activity.promisedDate
    }
  });

  // If payment was promised, schedule follow-up
  if (activity.outcome === 'payment_promised' && activity.promisedDate) {
    await scheduleFollowUp(invoiceId, activity.promisedDate);
  }
};
```

## Payment Plans

```typescript
interface PaymentPlan {
  id: string;
  customerId: string;
  totalAmount: number;

  // Plan details
  installments: number;
  frequency: 'weekly' | 'biweekly' | 'monthly';
  installmentAmount: number;
  startDate: Date;

  // Invoices included
  invoiceIds: string[];

  // Status
  status: 'pending_approval' | 'active' | 'completed' | 'defaulted';
  paidInstallments: number;
  remainingAmount: number;

  // Schedule
  schedule: PaymentPlanInstallment[];

  createdAt: Date;
  approvedAt?: Date;
  approvedBy?: string;
}

interface PaymentPlanInstallment {
  number: number;
  dueDate: Date;
  amount: number;
  status: 'pending' | 'paid' | 'overdue' | 'partial';
  paidAmount: number;
  paidDate?: Date;
}

// Create payment plan
export const createPaymentPlan = async (
  customerId: string,
  invoiceIds: string[],
  options: {
    installments: number;
    frequency: 'weekly' | 'biweekly' | 'monthly';
    startDate: Date;
  }
): Promise<PaymentPlan> => {
  const invoices = await prisma.invoice.findMany({
    where: { id: { in: invoiceIds } }
  });

  const totalAmount = invoices.reduce((sum, inv) => sum + Number(inv.balance), 0);
  const installmentAmount = Math.ceil(totalAmount / options.installments);

  // Generate schedule
  const schedule: PaymentPlanInstallment[] = [];
  let currentDate = options.startDate;

  for (let i = 0; i < options.installments; i++) {
    const isLast = i === options.installments - 1;
    const amount = isLast
      ? totalAmount - (installmentAmount * (options.installments - 1))
      : installmentAmount;

    schedule.push({
      number: i + 1,
      dueDate: currentDate,
      amount,
      status: 'pending',
      paidAmount: 0
    });

    currentDate = addInterval(currentDate, options.frequency);
  }

  const plan = await prisma.paymentPlan.create({
    data: {
      customerId,
      totalAmount,
      installments: options.installments,
      frequency: options.frequency,
      installmentAmount,
      startDate: options.startDate,
      invoiceIds,
      status: 'PENDING_APPROVAL',
      paidInstallments: 0,
      remainingAmount: totalAmount,
      schedule: { create: schedule }
    }
  });

  return plan;
};

// Record installment payment
export const recordInstallmentPayment = async (
  planId: string,
  installmentNumber: number,
  amount: number
) => {
  const plan = await prisma.paymentPlan.findUnique({
    where: { id: planId },
    include: { schedule: true }
  });

  const installment = plan.schedule.find(s => s.number === installmentNumber);
  const newPaidAmount = installment.paidAmount + amount;
  const isPaid = newPaidAmount >= installment.amount;

  await prisma.paymentPlanInstallment.update({
    where: { id: installment.id },
    data: {
      paidAmount: newPaidAmount,
      status: isPaid ? 'PAID' : 'PARTIAL',
      paidDate: isPaid ? new Date() : undefined
    }
  });

  // Apply payment to invoices
  await applyPaymentToInvoices(plan.invoiceIds, amount);

  // Update plan
  const paidInstallments = plan.schedule.filter(s =>
    s.number === installmentNumber ? isPaid : s.status === 'PAID'
  ).length;

  await prisma.paymentPlan.update({
    where: { id: planId },
    data: {
      paidInstallments,
      remainingAmount: { decrement: amount },
      status: paidInstallments === plan.installments ? 'COMPLETED' : 'ACTIVE'
    }
  });
};
```

## Components

### CollectionDashboard

```tsx
const CollectionDashboard = () => {
  const { data } = useQuery({
    queryKey: ['collection-stats'],
    queryFn: () => fetch('/api/debt/collections/stats').then(r => r.json())
  });

  return (
    <div className="space-y-6">
      {/* Stats cards */}
      <div className="grid grid-cols-4 gap-4">
        <StatsCard
          title="Total Overdue"
          value={formatCurrency(data?.totalOverdue)}
          trend={data?.overdueTrend}
        />
        <StatsCard
          title="In Collection"
          value={data?.inCollectionCount}
          subtitle={formatCurrency(data?.inCollectionAmount)}
        />
        <StatsCard
          title="Promised Payments"
          value={formatCurrency(data?.promisedAmount)}
          subtitle={`${data?.promisedCount} customers`}
        />
        <StatsCard
          title="Collection Rate"
          value={`${data?.collectionRate}%`}
          trend={data?.collectionRateTrend}
        />
      </div>

      {/* Tasks */}
      <CollectionTaskList />

      {/* Recent activity */}
      <CollectionActivityFeed />
    </div>
  );
};
```

### RecordCollectionModal

```tsx
const RecordCollectionModal = ({ invoice, onClose }: RecordCollectionModalProps) => {
  const form = useForm<CollectionActivityForm>();

  const { mutate: record } = useMutation({
    mutationFn: (data: CollectionActivityForm) =>
      fetch(`/api/debt/invoices/${invoice.id}/collection`, {
        method: 'POST',
        body: JSON.stringify(data)
      })
  });

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Record Collection Activity</DialogTitle>
        </DialogHeader>

        <form onSubmit={form.handleSubmit(data => record(data))}>
          <div className="space-y-4">
            <div>
              <Label>Contact Method</Label>
              <Select {...form.register('contactMethod')}>
                <SelectItem value="phone">Phone Call</SelectItem>
                <SelectItem value="email">Email</SelectItem>
                <SelectItem value="sms">SMS</SelectItem>
                <SelectItem value="in_person">In Person</SelectItem>
              </Select>
            </div>

            <div>
              <Label>Outcome</Label>
              <Select {...form.register('outcome')}>
                <SelectItem value="spoke_to_customer">Spoke to Customer</SelectItem>
                <SelectItem value="payment_promised">Payment Promised</SelectItem>
                <SelectItem value="payment_received">Payment Received</SelectItem>
                <SelectItem value="left_message">Left Message</SelectItem>
                <SelectItem value="no_answer">No Answer</SelectItem>
                <SelectItem value="dispute">Dispute Raised</SelectItem>
                <SelectItem value="refused_to_pay">Refused to Pay</SelectItem>
              </Select>
            </div>

            {form.watch('outcome') === 'payment_promised' && (
              <>
                <div>
                  <Label>Promised Amount</Label>
                  <Input
                    type="number"
                    {...form.register('promisedAmount', { valueAsNumber: true })}
                  />
                </div>
                <div>
                  <Label>Promised Date</Label>
                  <DatePicker {...form.register('promisedDate')} />
                </div>
              </>
            )}

            <div>
              <Label>Notes</Label>
              <Textarea {...form.register('notes')} rows={3} />
            </div>

            <Button type="submit" className="w-full">
              Save Activity
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
};
```
