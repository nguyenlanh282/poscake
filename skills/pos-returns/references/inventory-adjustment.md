# Inventory Adjustment

Điều chỉnh tồn kho sau khi xử lý đổi trả.

## Overview

Inventory adjustment xử lý việc cập nhật stock sau khi nhận hàng trả về - restock, mark as damaged, hoặc dispose.

## Data Model

```typescript
interface InventoryAdjustment {
  id: string;
  adjustmentNumber: string;    // ADJ-2024-0001

  // Reference
  rmaId: string;
  rmaItemId: string;
  productId: string;
  variantId?: string;
  warehouseId: string;

  // Quantities
  quantity: number;
  previousStock: number;
  newStock: number;

  // Action
  action: AdjustmentAction;
  reason: AdjustmentReason;

  // Condition
  condition: ItemCondition;

  // Costing
  unitCost: number;
  totalCost: number;
  writeOffAmount?: number;

  // Dates
  adjustedAt: Date;
  adjustedBy: string;
  notes?: string;
}

type AdjustmentAction = 'restock' | 'damaged' | 'dispose' | 'vendor_return' | 'quarantine';

type AdjustmentReason =
  | 'return_good_condition'
  | 'return_minor_damage'
  | 'return_defective'
  | 'return_expired'
  | 'quality_fail'
  | 'manual_adjustment';

interface ItemCondition {
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  description: string;
  reselable: boolean;
  discountRequired?: number;   // Percentage discount if resold
}

const conditionGrades: Record<string, ItemCondition> = {
  A: { grade: 'A', description: 'Like new, original packaging', reselable: true, discountRequired: 0 },
  B: { grade: 'B', description: 'Good condition, opened packaging', reselable: true, discountRequired: 10 },
  C: { grade: 'C', description: 'Minor signs of use/wear', reselable: true, discountRequired: 30 },
  D: { grade: 'D', description: 'Significant wear, functional', reselable: true, discountRequired: 50 },
  F: { grade: 'F', description: 'Damaged/non-functional', reselable: false }
};
```

## Action Handlers

```typescript
// services/inventoryAdjustment.ts

export const processReturnAdjustment = async (
  rmaItemId: string,
  action: AdjustmentAction,
  inspectedBy: string,
  condition: ItemCondition,
  notes?: string
): Promise<InventoryAdjustment> => {
  const rmaItem = await prisma.rmaItem.findUnique({
    where: { id: rmaItemId },
    include: {
      rma: true,
      product: true
    }
  });

  const warehouseId = await getReturnsWarehouse();

  switch (action) {
    case 'restock':
      return await restockItem(rmaItem, warehouseId, condition, inspectedBy, notes);
    case 'damaged':
      return await markAsDamaged(rmaItem, warehouseId, condition, inspectedBy, notes);
    case 'dispose':
      return await disposeItem(rmaItem, warehouseId, inspectedBy, notes);
    case 'vendor_return':
      return await createVendorReturn(rmaItem, condition, inspectedBy, notes);
    case 'quarantine':
      return await quarantineItem(rmaItem, warehouseId, inspectedBy, notes);
  }
};

// Restock item to sellable inventory
const restockItem = async (
  rmaItem: RMAItem,
  warehouseId: string,
  condition: ItemCondition,
  inspectedBy: string,
  notes?: string
): Promise<InventoryAdjustment> => {
  const adjustmentNumber = await generateAdjustmentNumber();

  // Get current stock
  const inventory = await prisma.inventory.findFirst({
    where: {
      productId: rmaItem.productId,
      warehouseId
    }
  });

  const previousStock = inventory?.quantity || 0;
  const newStock = previousStock + rmaItem.quantity;

  // Update inventory
  await prisma.inventory.upsert({
    where: {
      productId_warehouseId: {
        productId: rmaItem.productId,
        warehouseId
      }
    },
    update: { quantity: { increment: rmaItem.quantity } },
    create: {
      productId: rmaItem.productId,
      warehouseId,
      quantity: rmaItem.quantity
    }
  });

  // Create stock movement
  await prisma.stockMovement.create({
    data: {
      productId: rmaItem.productId,
      warehouseId,
      type: 'RETURN',
      quantity: rmaItem.quantity,
      referenceType: 'RMA',
      referenceId: rmaItem.rmaId
    }
  });

  // If condition requires discount, update product or create variant
  if (condition.discountRequired && condition.discountRequired > 0) {
    await handleDiscountedRestock(rmaItem, condition);
  }

  // Create adjustment record
  const adjustment = await prisma.inventoryAdjustment.create({
    data: {
      adjustmentNumber,
      rmaId: rmaItem.rmaId,
      rmaItemId: rmaItem.id,
      productId: rmaItem.productId,
      warehouseId,
      quantity: rmaItem.quantity,
      previousStock,
      newStock,
      action: 'RESTOCK',
      reason: 'RETURN_GOOD_CONDITION',
      condition: condition.grade,
      unitCost: rmaItem.unitPrice,
      totalCost: rmaItem.unitPrice * rmaItem.quantity,
      adjustedBy: inspectedBy,
      adjustedAt: new Date(),
      notes
    }
  });

  return adjustment;
};

// Mark as damaged - separate damaged goods inventory
const markAsDamaged = async (
  rmaItem: RMAItem,
  warehouseId: string,
  condition: ItemCondition,
  inspectedBy: string,
  notes?: string
): Promise<InventoryAdjustment> => {
  const adjustmentNumber = await generateAdjustmentNumber();

  // Add to damaged goods location
  const damagedLocationId = await getDamagedGoodsLocation(warehouseId);

  await prisma.damagedInventory.create({
    data: {
      productId: rmaItem.productId,
      locationId: damagedLocationId,
      quantity: rmaItem.quantity,
      condition: condition.grade,
      conditionNotes: notes,
      rmaId: rmaItem.rmaId,
      status: 'PENDING_DECISION'
    }
  });

  const writeOffAmount = rmaItem.unitPrice * rmaItem.quantity;

  const adjustment = await prisma.inventoryAdjustment.create({
    data: {
      adjustmentNumber,
      rmaId: rmaItem.rmaId,
      rmaItemId: rmaItem.id,
      productId: rmaItem.productId,
      warehouseId,
      quantity: rmaItem.quantity,
      previousStock: 0,
      newStock: 0,
      action: 'DAMAGED',
      reason: 'RETURN_DEFECTIVE',
      condition: condition.grade,
      unitCost: rmaItem.unitPrice,
      totalCost: 0,
      writeOffAmount,
      adjustedBy: inspectedBy,
      adjustedAt: new Date(),
      notes
    }
  });

  return adjustment;
};

// Create vendor return
const createVendorReturn = async (
  rmaItem: RMAItem,
  condition: ItemCondition,
  inspectedBy: string,
  notes?: string
): Promise<InventoryAdjustment> => {
  const product = await prisma.product.findUnique({
    where: { id: rmaItem.productId },
    include: { supplier: true }
  });

  // Create vendor return request
  await prisma.vendorReturn.create({
    data: {
      supplierId: product.supplierId,
      rmaId: rmaItem.rmaId,
      items: {
        create: {
          productId: rmaItem.productId,
          quantity: rmaItem.quantity,
          reason: rmaItem.reason,
          condition: condition.grade
        }
      },
      status: 'PENDING',
      notes
    }
  });

  // Adjustment with pending vendor return
  const adjustment = await prisma.inventoryAdjustment.create({
    data: {
      adjustmentNumber: await generateAdjustmentNumber(),
      rmaId: rmaItem.rmaId,
      rmaItemId: rmaItem.id,
      productId: rmaItem.productId,
      warehouseId: await getReturnsWarehouse(),
      quantity: rmaItem.quantity,
      previousStock: 0,
      newStock: 0,
      action: 'VENDOR_RETURN',
      reason: 'RETURN_DEFECTIVE',
      condition: condition.grade,
      unitCost: rmaItem.unitPrice,
      totalCost: rmaItem.unitPrice * rmaItem.quantity,
      adjustedBy: inspectedBy,
      adjustedAt: new Date(),
      notes: `Pending vendor return to ${product.supplier.name}`
    }
  });

  return adjustment;
};
```

## Inspection Workflow

```typescript
interface InspectionChecklist {
  items: ChecklistItem[];
  requiredPhotos: boolean;
  gradeMatrix: GradeMatrix;
}

interface ChecklistItem {
  id: string;
  category: string;
  question: string;
  type: 'pass_fail' | 'rating' | 'text';
  weight: number;              // For grade calculation
  required: boolean;
}

const inspectionChecklist: InspectionChecklist = {
  items: [
    { id: 'packaging', category: 'Packaging', question: 'Original packaging intact?', type: 'pass_fail', weight: 10, required: true },
    { id: 'tags', category: 'Packaging', question: 'All tags attached?', type: 'pass_fail', weight: 5, required: true },
    { id: 'accessories', category: 'Contents', question: 'All accessories included?', type: 'pass_fail', weight: 15, required: true },
    { id: 'physical', category: 'Condition', question: 'Physical condition', type: 'rating', weight: 30, required: true },
    { id: 'functional', category: 'Condition', question: 'Functional test passed?', type: 'pass_fail', weight: 30, required: true },
    { id: 'cleanliness', category: 'Condition', question: 'Clean/no odors?', type: 'pass_fail', weight: 10, required: true },
    { id: 'notes', category: 'Notes', question: 'Additional observations', type: 'text', weight: 0, required: false }
  ],
  requiredPhotos: true,
  gradeMatrix: {
    90: 'A',
    75: 'B',
    50: 'C',
    25: 'D',
    0: 'F'
  }
};

// Calculate grade from checklist
const calculateGrade = (answers: Record<string, any>): string => {
  let totalWeight = 0;
  let earnedWeight = 0;

  for (const item of inspectionChecklist.items) {
    if (item.weight === 0) continue;
    totalWeight += item.weight;

    const answer = answers[item.id];
    if (item.type === 'pass_fail' && answer === true) {
      earnedWeight += item.weight;
    } else if (item.type === 'rating') {
      earnedWeight += (answer / 5) * item.weight;
    }
  }

  const score = (earnedWeight / totalWeight) * 100;

  for (const [threshold, grade] of Object.entries(inspectionChecklist.gradeMatrix).sort((a, b) => Number(b[0]) - Number(a[0]))) {
    if (score >= Number(threshold)) return grade;
  }

  return 'F';
};
```

## Components

### InspectionForm

```tsx
const InspectionForm = ({ rmaItem, onComplete }: InspectionFormProps) => {
  const [answers, setAnswers] = useState<Record<string, any>>({});
  const [photos, setPhotos] = useState<string[]>([]);
  const [action, setAction] = useState<AdjustmentAction>('restock');
  const [notes, setNotes] = useState('');

  const grade = useMemo(() => calculateGrade(answers), [answers]);
  const condition = conditionGrades[grade];

  // Auto-suggest action based on grade
  useEffect(() => {
    if (grade === 'F') setAction('damaged');
    else if (grade === 'D') setAction('damaged');
    else setAction('restock');
  }, [grade]);

  return (
    <div className="space-y-6">
      {/* Checklist */}
      <Card>
        <CardHeader>
          <CardTitle>Inspection Checklist</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {inspectionChecklist.items.map(item => (
            <div key={item.id} className="flex items-center justify-between">
              <Label>{item.question}</Label>
              {item.type === 'pass_fail' && (
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    variant={answers[item.id] === true ? 'default' : 'outline'}
                    onClick={() => setAnswers({ ...answers, [item.id]: true })}
                  >
                    <Check className="h-4 w-4" />
                  </Button>
                  <Button
                    size="sm"
                    variant={answers[item.id] === false ? 'destructive' : 'outline'}
                    onClick={() => setAnswers({ ...answers, [item.id]: false })}
                  >
                    <X className="h-4 w-4" />
                  </Button>
                </div>
              )}
              {item.type === 'rating' && (
                <RatingInput
                  value={answers[item.id] || 0}
                  onChange={(v) => setAnswers({ ...answers, [item.id]: v })}
                  max={5}
                />
              )}
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Photos */}
      <Card>
        <CardHeader>
          <CardTitle>Inspection Photos</CardTitle>
        </CardHeader>
        <CardContent>
          <FileUpload
            accept="image/*"
            maxFiles={10}
            onUpload={setPhotos}
          />
        </CardContent>
      </Card>

      {/* Grade result */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-muted-foreground">Condition Grade</p>
              <p className="text-3xl font-bold">{grade}</p>
              <p className="text-sm">{condition.description}</p>
            </div>
            <Badge variant={condition.reselable ? 'default' : 'destructive'}>
              {condition.reselable ? 'Resellable' : 'Not Resellable'}
            </Badge>
          </div>
        </CardContent>
      </Card>

      {/* Action */}
      <Card>
        <CardHeader>
          <CardTitle>Inventory Action</CardTitle>
        </CardHeader>
        <CardContent>
          <RadioGroup value={action} onValueChange={(v) => setAction(v as AdjustmentAction)}>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="restock" id="restock" />
              <Label htmlFor="restock">Restock to inventory</Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="damaged" id="damaged" />
              <Label htmlFor="damaged">Mark as damaged goods</Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="vendor_return" id="vendor_return" />
              <Label htmlFor="vendor_return">Return to vendor</Label>
            </div>
            <div className="flex items-center space-x-2">
              <RadioGroupItem value="dispose" id="dispose" />
              <Label htmlFor="dispose">Dispose/Write-off</Label>
            </div>
          </RadioGroup>
        </CardContent>
      </Card>

      {/* Notes */}
      <Card>
        <CardHeader>
          <CardTitle>Notes</CardTitle>
        </CardHeader>
        <CardContent>
          <Textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Any additional observations..."
          />
        </CardContent>
      </Card>

      <Button
        onClick={() => onComplete({ answers, photos, action, condition, notes })}
        className="w-full"
      >
        Complete Inspection
      </Button>
    </div>
  );
};
```
