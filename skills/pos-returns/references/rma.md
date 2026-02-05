# Return Authorization (RMA)

Quy trình tạo và quản lý RMA (Return Merchandise Authorization).

## Overview

RMA system quản lý requests đổi trả từ khi khách hàng yêu cầu đến khi hoàn tất xử lý.

## Data Model

```typescript
interface RMA {
  id: string;
  rmaNumber: string;           // RMA-2024-0001

  // References
  orderId: string;
  orderNumber: string;
  customerId: string;
  customerName: string;

  // Type and reason
  type: RMAType;
  reason: ReturnReason;
  reasonDetail?: string;

  // Items
  items: RMAItem[];

  // Status
  status: RMAStatus;
  currentStep: RMAStep;

  // Workflow
  requestedAt: Date;
  approvedAt?: Date;
  shippedAt?: Date;
  receivedAt?: Date;
  inspectedAt?: Date;
  completedAt?: Date;
  cancelledAt?: Date;

  // Staff
  approvedBy?: string;
  inspectedBy?: string;
  processedBy?: string;

  // Shipping
  returnShippingLabel?: string;
  returnTrackingNumber?: string;
  returnCarrier?: string;

  // Notes
  customerNotes?: string;
  internalNotes?: string;
  inspectionNotes?: string;

  // Attachments
  customerPhotos?: string[];
  inspectionPhotos?: string[];
}

type RMAType = 'refund' | 'exchange' | 'store_credit' | 'repair';
type ReturnReason = 'defective' | 'wrong_item' | 'not_as_described' | 'changed_mind' | 'damaged_shipping' | 'size_issue' | 'other';
type RMAStatus = 'pending' | 'approved' | 'rejected' | 'shipped' | 'received' | 'inspecting' | 'processing' | 'completed' | 'cancelled';
type RMAStep = 'request' | 'approval' | 'shipping' | 'receiving' | 'inspection' | 'processing' | 'complete';

interface RMAItem {
  id: string;
  orderItemId: string;
  productId: string;
  productName: string;
  sku: string;
  variantName?: string;
  quantity: number;
  unitPrice: number;
  reason: ReturnReason;
  condition?: ItemCondition;
  inspectionResult?: InspectionResult;
  action?: ItemAction;
}

type ItemCondition = 'new' | 'like_new' | 'good' | 'fair' | 'poor' | 'damaged';
type InspectionResult = 'pass' | 'fail' | 'partial';
type ItemAction = 'refund' | 'exchange' | 'restock' | 'dispose' | 'vendor_return';
```

## RMA Workflow

```typescript
const rmaWorkflow: WorkflowStep[] = [
  {
    step: 'request',
    status: 'pending',
    name: 'Request Submitted',
    description: 'Customer submitted return request',
    nextSteps: ['approval'],
    actions: ['approve', 'reject', 'request_info']
  },
  {
    step: 'approval',
    status: 'approved',
    name: 'Approved',
    description: 'Return request approved',
    nextSteps: ['shipping'],
    actions: ['generate_label', 'email_instructions']
  },
  {
    step: 'shipping',
    status: 'shipped',
    name: 'In Transit',
    description: 'Customer shipped items',
    nextSteps: ['receiving'],
    actions: ['track_shipment']
  },
  {
    step: 'receiving',
    status: 'received',
    name: 'Received',
    description: 'Items received at warehouse',
    nextSteps: ['inspection'],
    actions: ['start_inspection']
  },
  {
    step: 'inspection',
    status: 'inspecting',
    name: 'Inspection',
    description: 'Checking item conditions',
    nextSteps: ['processing'],
    actions: ['complete_inspection', 'reject_item']
  },
  {
    step: 'processing',
    status: 'processing',
    name: 'Processing',
    description: 'Processing refund/exchange',
    nextSteps: ['complete'],
    actions: ['process_refund', 'ship_exchange', 'issue_credit']
  },
  {
    step: 'complete',
    status: 'completed',
    name: 'Completed',
    description: 'Return fully processed',
    nextSteps: [],
    actions: []
  }
];
```

## Service Implementation

```typescript
// services/rma.ts

// Create RMA request
export const createRMA = async (
  orderId: string,
  items: { orderItemId: string; quantity: number; reason: ReturnReason }[],
  type: RMAType,
  customerNotes?: string,
  photos?: string[]
): Promise<RMA> => {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: {
      customer: true,
      items: { include: { product: true } }
    }
  });

  // Validate eligibility
  const evaluation = await evaluateReturnEligibility(orderId, items);
  if (!evaluation.allowed) {
    throw new Error(evaluation.reason);
  }

  const rmaNumber = await generateRMANumber();

  const rmaItems = items.map(item => {
    const orderItem = order.items.find(i => i.id === item.orderItemId);
    return {
      orderItemId: item.orderItemId,
      productId: orderItem.productId,
      productName: orderItem.product.name,
      sku: orderItem.product.sku,
      variantName: orderItem.variantName,
      quantity: item.quantity,
      unitPrice: orderItem.unitPrice,
      reason: item.reason
    };
  });

  const rma = await prisma.rma.create({
    data: {
      rmaNumber,
      orderId,
      orderNumber: order.orderNumber,
      customerId: order.customerId,
      customerName: order.customer.name,
      type,
      reason: items[0].reason,
      items: { create: rmaItems },
      status: evaluation.requiresApproval ? 'PENDING' : 'APPROVED',
      currentStep: evaluation.requiresApproval ? 'REQUEST' : 'APPROVAL',
      customerNotes,
      customerPhotos: photos,
      requestedAt: new Date(),
      approvedAt: evaluation.requiresApproval ? undefined : new Date()
    }
  });

  // Send confirmation email
  await sendRMAConfirmation(rma);

  // If auto-approved, generate return label
  if (!evaluation.requiresApproval) {
    await generateReturnLabel(rma.id);
  }

  return rma;
};

// Approve RMA
export const approveRMA = async (
  rmaId: string,
  approvedBy: string,
  notes?: string
): Promise<RMA> => {
  const rma = await prisma.rma.update({
    where: { id: rmaId },
    data: {
      status: 'APPROVED',
      currentStep: 'APPROVAL',
      approvedAt: new Date(),
      approvedBy,
      internalNotes: notes
    }
  });

  // Generate return label
  await generateReturnLabel(rmaId);

  // Send approval email with instructions
  await sendRMAApprovalEmail(rma);

  return rma;
};

// Reject RMA
export const rejectRMA = async (
  rmaId: string,
  rejectedBy: string,
  reason: string
): Promise<RMA> => {
  const rma = await prisma.rma.update({
    where: { id: rmaId },
    data: {
      status: 'REJECTED',
      internalNotes: `Rejected: ${reason}`
    }
  });

  await sendRMARejectionEmail(rma, reason);

  return rma;
};

// Mark as received
export const receiveRMA = async (
  rmaId: string,
  receivedBy: string
): Promise<RMA> => {
  return await prisma.rma.update({
    where: { id: rmaId },
    data: {
      status: 'RECEIVED',
      currentStep: 'RECEIVING',
      receivedAt: new Date()
    }
  });
};

// Complete inspection
export const completeInspection = async (
  rmaId: string,
  inspectedBy: string,
  items: {
    itemId: string;
    condition: ItemCondition;
    result: InspectionResult;
    action: ItemAction;
    notes?: string;
  }[],
  photos?: string[]
): Promise<RMA> => {
  for (const item of items) {
    await prisma.rmaItem.update({
      where: { id: item.itemId },
      data: {
        condition: item.condition,
        inspectionResult: item.result,
        action: item.action
      }
    });
  }

  return await prisma.rma.update({
    where: { id: rmaId },
    data: {
      status: 'PROCESSING',
      currentStep: 'PROCESSING',
      inspectedAt: new Date(),
      inspectedBy,
      inspectionNotes: items.map(i => i.notes).filter(Boolean).join('; '),
      inspectionPhotos: photos
    }
  });
};
```

## Return Label Generation

```typescript
// services/returnShipping.ts
import EasyPost from '@easypost/api';

const easypost = new EasyPost(process.env.EASYPOST_API_KEY);

export const generateReturnLabel = async (rmaId: string): Promise<string> => {
  const rma = await prisma.rma.findUnique({
    where: { id: rmaId },
    include: {
      customer: true,
      items: true
    }
  });

  // Create shipment
  const shipment = await easypost.Shipment.create({
    from_address: {
      name: rma.customerName,
      street1: rma.customer.address,
      city: rma.customer.city,
      state: rma.customer.province,
      zip: rma.customer.postalCode,
      country: 'VN',
      phone: rma.customer.phone
    },
    to_address: {
      company: 'Returns Center',
      street1: process.env.RETURNS_ADDRESS,
      city: process.env.RETURNS_CITY,
      state: process.env.RETURNS_STATE,
      zip: process.env.RETURNS_ZIP,
      country: 'VN'
    },
    parcel: {
      weight: calculateWeight(rma.items),
      length: 30,
      width: 20,
      height: 10
    },
    is_return: true
  });

  // Buy the cheapest rate
  const lowestRate = shipment.lowestRate();
  const boughtShipment = await easypost.Shipment.buy(shipment.id, lowestRate);

  // Update RMA
  await prisma.rma.update({
    where: { id: rmaId },
    data: {
      returnShippingLabel: boughtShipment.postage_label.label_url,
      returnTrackingNumber: boughtShipment.tracking_code,
      returnCarrier: lowestRate.carrier
    }
  });

  return boughtShipment.postage_label.label_url;
};
```

## Components

### RMARequestForm

```tsx
const RMARequestForm = ({ order }: { order: Order }) => {
  const [selectedItems, setSelectedItems] = useState<Map<string, RMAItemSelection>>(new Map());
  const [type, setType] = useState<RMAType>('refund');
  const [photos, setPhotos] = useState<string[]>([]);
  const [notes, setNotes] = useState('');

  const { mutate: createRMA, isLoading } = useMutation({
    mutationFn: () => fetch('/api/returns', {
      method: 'POST',
      body: JSON.stringify({
        orderId: order.id,
        type,
        items: Array.from(selectedItems.entries()).map(([itemId, sel]) => ({
          orderItemId: itemId,
          quantity: sel.quantity,
          reason: sel.reason
        })),
        customerNotes: notes,
        photos
      })
    })
  });

  return (
    <div className="space-y-6">
      {/* Item selection */}
      <Card>
        <CardHeader>
          <CardTitle>Select Items to Return</CardTitle>
        </CardHeader>
        <CardContent>
          {order.items.map(item => (
            <ReturnItemRow
              key={item.id}
              item={item}
              selected={selectedItems.has(item.id)}
              selection={selectedItems.get(item.id)}
              onSelect={(sel) => {
                const newMap = new Map(selectedItems);
                if (sel) {
                  newMap.set(item.id, sel);
                } else {
                  newMap.delete(item.id);
                }
                setSelectedItems(newMap);
              }}
            />
          ))}
        </CardContent>
      </Card>

      {/* Return type */}
      <Card>
        <CardHeader>
          <CardTitle>What would you like?</CardTitle>
        </CardHeader>
        <CardContent>
          <RadioGroup value={type} onValueChange={(v) => setType(v as RMAType)}>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="refund" id="refund" />
              <Label htmlFor="refund">Refund to original payment method</Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="store_credit" id="store_credit" />
              <Label htmlFor="store_credit">Store credit</Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="exchange" id="exchange" />
              <Label htmlFor="exchange">Exchange for different item</Label>
            </div>
          </RadioGroup>
        </CardContent>
      </Card>

      {/* Photos */}
      <Card>
        <CardHeader>
          <CardTitle>Upload Photos (Optional)</CardTitle>
          <CardDescription>
            Photos help us process your return faster
          </CardDescription>
        </CardHeader>
        <CardContent>
          <FileUpload
            accept="image/*"
            maxFiles={5}
            onUpload={setPhotos}
          />
        </CardContent>
      </Card>

      {/* Notes */}
      <Card>
        <CardHeader>
          <CardTitle>Additional Notes</CardTitle>
        </CardHeader>
        <CardContent>
          <Textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Any additional details about your return..."
          />
        </CardContent>
      </Card>

      <Button
        onClick={() => createRMA()}
        disabled={selectedItems.size === 0 || isLoading}
        className="w-full"
      >
        {isLoading ? 'Submitting...' : 'Submit Return Request'}
      </Button>
    </div>
  );
};
```

### RMATimeline

```tsx
const RMATimeline = ({ rma }: { rma: RMA }) => {
  const steps = [
    { key: 'request', label: 'Requested', date: rma.requestedAt, icon: FileText },
    { key: 'approval', label: 'Approved', date: rma.approvedAt, icon: CheckCircle },
    { key: 'shipping', label: 'Shipped', date: rma.shippedAt, icon: Truck },
    { key: 'receiving', label: 'Received', date: rma.receivedAt, icon: Package },
    { key: 'inspection', label: 'Inspected', date: rma.inspectedAt, icon: Search },
    { key: 'complete', label: 'Completed', date: rma.completedAt, icon: CheckCircle2 }
  ];

  const currentIndex = steps.findIndex(s => s.key === rma.currentStep);

  return (
    <div className="flex justify-between">
      {steps.map((step, index) => {
        const Icon = step.icon;
        const isActive = index <= currentIndex;
        const isCurrent = step.key === rma.currentStep;

        return (
          <div key={step.key} className="flex flex-col items-center">
            <div className={cn(
              "w-10 h-10 rounded-full flex items-center justify-center",
              isActive ? "bg-primary text-white" : "bg-muted text-muted-foreground",
              isCurrent && "ring-2 ring-primary ring-offset-2"
            )}>
              <Icon className="h-5 w-5" />
            </div>
            <p className="text-sm font-medium mt-2">{step.label}</p>
            {step.date && (
              <p className="text-xs text-muted-foreground">
                {formatDate(step.date)}
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
};
```
