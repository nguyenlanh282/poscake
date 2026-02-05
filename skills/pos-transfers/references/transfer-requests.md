# Transfer Requests

Tạo và quản lý yêu cầu chuyển kho hàng hóa.

## Overview

Transfer requests cho phép yêu cầu chuyển stock từ warehouse này sang warehouse khác để cân bằng tồn kho.

## Data Model

```typescript
interface TransferRequest {
  id: string;
  transferNumber: string;      // TRF-2024-0001

  // Locations
  sourceWarehouseId: string;
  sourceWarehouse: Warehouse;
  destinationWarehouseId: string;
  destinationWarehouse: Warehouse;

  // Details
  type: TransferType;
  priority: TransferPriority;
  reason: TransferReason;
  reasonNotes?: string;

  // Items
  items: TransferItem[];
  totalQuantity: number;
  totalCost: number;
  totalWeight?: number;

  // Status
  status: TransferStatus;

  // Dates
  requestedAt: Date;
  scheduledDate?: Date;
  expectedArrival?: Date;

  // Staff
  requestedBy: string;
  approvedBy?: string;

  // Notes
  notes?: string;
  internalNotes?: string;
}

type TransferType =
  | 'replenishment'     // Stock low at destination
  | 'rebalance'         // Even out stock levels
  | 'consolidation'     // Merge stock to one location
  | 'new_store'         // Stock for new location
  | 'seasonal'          // Seasonal demand shift
  | 'emergency';        // Urgent need

type TransferPriority = 'low' | 'normal' | 'high' | 'urgent';

type TransferReason =
  | 'low_stock'
  | 'overstock'
  | 'sales_velocity'
  | 'promotional'
  | 'new_location'
  | 'closing_location'
  | 'other';

type TransferStatus =
  | 'draft'
  | 'pending'           // Awaiting approval
  | 'approved'
  | 'rejected'
  | 'picking'           // Being picked at source
  | 'packed'
  | 'shipped'
  | 'in_transit'
  | 'received'
  | 'completed'
  | 'cancelled';

interface TransferItem {
  id: string;
  productId: string;
  product: Product;
  sku: string;
  variantId?: string;

  // Quantities
  requestedQty: number;
  availableQty: number;     // At source at time of request
  pickedQty?: number;
  shippedQty?: number;
  receivedQty?: number;

  // Source/Dest stock
  sourceStock: number;      // Before transfer
  destStock: number;        // Before transfer

  // Costing
  unitCost: number;
  totalCost: number;

  // Status
  status: ItemStatus;
  notes?: string;
}

type ItemStatus = 'pending' | 'picked' | 'shipped' | 'received' | 'discrepancy';
```

## Service Implementation

```typescript
// services/transferRequest.ts

// Create transfer request
export const createTransferRequest = async (
  data: CreateTransferInput,
  requestedBy: string
): Promise<TransferRequest> => {
  const transferNumber = await generateTransferNumber();

  // Validate source stock
  const stockValidation = await validateSourceStock(
    data.sourceWarehouseId,
    data.items
  );

  if (!stockValidation.valid) {
    throw new Error(`Insufficient stock: ${stockValidation.errors.join(', ')}`);
  }

  // Calculate costs and totals
  const items = await Promise.all(data.items.map(async item => {
    const product = await prisma.product.findUnique({
      where: { id: item.productId }
    });

    const sourceStock = await getStockLevel(item.productId, data.sourceWarehouseId);
    const destStock = await getStockLevel(item.productId, data.destinationWarehouseId);

    return {
      productId: item.productId,
      sku: product.sku,
      variantId: item.variantId,
      requestedQty: item.quantity,
      availableQty: sourceStock,
      sourceStock,
      destStock,
      unitCost: product.costPrice || 0,
      totalCost: (product.costPrice || 0) * item.quantity,
      status: 'PENDING'
    };
  }));

  const totalQuantity = items.reduce((sum, i) => sum + i.requestedQty, 0);
  const totalCost = items.reduce((sum, i) => sum + i.totalCost, 0);

  // Determine if auto-approval applies
  const autoApprove = await checkAutoApproval(totalCost, totalQuantity);

  const transfer = await prisma.transferRequest.create({
    data: {
      transferNumber,
      sourceWarehouseId: data.sourceWarehouseId,
      destinationWarehouseId: data.destinationWarehouseId,
      type: data.type,
      priority: data.priority,
      reason: data.reason,
      reasonNotes: data.reasonNotes,
      items: { create: items },
      totalQuantity,
      totalCost,
      status: autoApprove ? 'APPROVED' : 'PENDING',
      requestedAt: new Date(),
      scheduledDate: data.scheduledDate,
      requestedBy,
      approvedBy: autoApprove ? 'system' : undefined,
      notes: data.notes
    },
    include: {
      items: { include: { product: true } },
      sourceWarehouse: true,
      destinationWarehouse: true
    }
  });

  // Reserve stock at source (soft hold)
  await reserveStock(transfer.id, data.sourceWarehouseId, items);

  // Notify relevant parties
  if (!autoApprove) {
    await notifyApprovers(transfer);
  }

  return transfer;
};

// Validate source stock availability
const validateSourceStock = async (
  warehouseId: string,
  items: { productId: string; quantity: number }[]
): Promise<{ valid: boolean; errors: string[] }> => {
  const errors: string[] = [];

  for (const item of items) {
    const stock = await getStockLevel(item.productId, warehouseId);
    const reserved = await getReservedStock(item.productId, warehouseId);
    const available = stock - reserved;

    if (item.quantity > available) {
      const product = await prisma.product.findUnique({
        where: { id: item.productId },
        select: { name: true }
      });
      errors.push(`${product.name}: requested ${item.quantity}, available ${available}`);
    }
  }

  return { valid: errors.length === 0, errors };
};

// Check if transfer can be auto-approved
const checkAutoApproval = async (
  totalCost: number,
  totalQuantity: number
): Promise<boolean> => {
  const settings = await getTransferSettings();

  if (!settings.autoApprove.enabled) return false;
  if (totalCost > settings.autoApprove.maxValue) return false;
  if (totalQuantity > settings.autoApprove.maxItems) return false;

  return true;
};
```

## Stock Suggestion Engine

```typescript
interface TransferSuggestion {
  sourceWarehouseId: string;
  sourceWarehouse: string;
  destinationWarehouseId: string;
  destinationWarehouse: string;
  productId: string;
  productName: string;
  sku: string;
  suggestedQty: number;
  reason: TransferReason;
  priority: TransferPriority;
  sourceStock: number;
  destStock: number;
  destReorderPoint: number;
  savingsEstimate?: number;
}

export const generateTransferSuggestions = async (): Promise<TransferSuggestion[]> => {
  const suggestions: TransferSuggestion[] = [];

  // Get all warehouses with stock data
  const warehouses = await prisma.warehouse.findMany({
    where: { isActive: true },
    include: {
      inventory: {
        include: { product: true }
      }
    }
  });

  // Analyze each product across warehouses
  const productIds = [...new Set(
    warehouses.flatMap(w => w.inventory.map(i => i.productId))
  )];

  for (const productId of productIds) {
    const stockByWarehouse = warehouses.map(w => ({
      warehouseId: w.id,
      warehouseName: w.name,
      stock: w.inventory.find(i => i.productId === productId)?.quantity || 0,
      reorderPoint: w.inventory.find(i => i.productId === productId)?.reorderPoint || 0,
      salesVelocity: 0 // Calculate from sales data
    }));

    // Get sales velocity for each warehouse
    for (const ws of stockByWarehouse) {
      ws.salesVelocity = await getSalesVelocity(productId, ws.warehouseId, 30);
    }

    // Find locations that need stock
    const needStock = stockByWarehouse.filter(w =>
      w.stock < w.reorderPoint ||
      (w.salesVelocity > 0 && w.stock / w.salesVelocity < 7) // Less than 1 week stock
    );

    // Find locations with excess stock
    const hasExcess = stockByWarehouse.filter(w =>
      w.stock > w.reorderPoint * 3 || // More than 3x reorder point
      (w.salesVelocity > 0 && w.stock / w.salesVelocity > 90) // More than 3 months stock
    );

    // Generate suggestions
    for (const dest of needStock) {
      for (const source of hasExcess) {
        if (source.warehouseId === dest.warehouseId) continue;

        const transferQty = Math.min(
          source.stock - source.reorderPoint, // Don't go below reorder point at source
          dest.reorderPoint - dest.stock + (dest.salesVelocity * 14) // Fill to reorder + 2 weeks
        );

        if (transferQty > 0) {
          const product = await prisma.product.findUnique({
            where: { id: productId }
          });

          suggestions.push({
            sourceWarehouseId: source.warehouseId,
            sourceWarehouse: source.warehouseName,
            destinationWarehouseId: dest.warehouseId,
            destinationWarehouse: dest.warehouseName,
            productId,
            productName: product.name,
            sku: product.sku,
            suggestedQty: Math.floor(transferQty),
            reason: dest.stock < dest.reorderPoint ? 'low_stock' : 'sales_velocity',
            priority: dest.stock === 0 ? 'urgent' : dest.stock < dest.reorderPoint ? 'high' : 'normal',
            sourceStock: source.stock,
            destStock: dest.stock,
            destReorderPoint: dest.reorderPoint
          });
        }
      }
    }
  }

  return suggestions.sort((a, b) => {
    const priorityOrder = { urgent: 0, high: 1, normal: 2, low: 3 };
    return priorityOrder[a.priority] - priorityOrder[b.priority];
  });
};
```

## Components

### CreateTransferForm

```tsx
const CreateTransferForm = () => {
  const form = useForm<CreateTransferInput>();
  const [items, setItems] = useState<TransferItemInput[]>([]);

  const { data: warehouses } = useQuery({
    queryKey: ['warehouses'],
    queryFn: () => fetch('/api/warehouses').then(r => r.json())
  });

  const sourceId = form.watch('sourceWarehouseId');
  const { data: sourceStock } = useQuery({
    queryKey: ['warehouse-stock', sourceId],
    queryFn: () => fetch(`/api/warehouses/${sourceId}/stock`).then(r => r.json()),
    enabled: !!sourceId
  });

  return (
    <form onSubmit={form.handleSubmit(handleSubmit)} className="space-y-6">
      {/* Warehouse Selection */}
      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>Source Warehouse</Label>
          <Select {...form.register('sourceWarehouseId')}>
            {warehouses?.map((w: Warehouse) => (
              <SelectItem key={w.id} value={w.id}>{w.name}</SelectItem>
            ))}
          </Select>
        </div>
        <div>
          <Label>Destination Warehouse</Label>
          <Select {...form.register('destinationWarehouseId')}>
            {warehouses?.filter(w => w.id !== sourceId).map((w: Warehouse) => (
              <SelectItem key={w.id} value={w.id}>{w.name}</SelectItem>
            ))}
          </Select>
        </div>
      </div>

      {/* Transfer Details */}
      <div className="grid grid-cols-3 gap-4">
        <div>
          <Label>Type</Label>
          <Select {...form.register('type')}>
            <SelectItem value="replenishment">Replenishment</SelectItem>
            <SelectItem value="rebalance">Rebalance</SelectItem>
            <SelectItem value="consolidation">Consolidation</SelectItem>
            <SelectItem value="emergency">Emergency</SelectItem>
          </Select>
        </div>
        <div>
          <Label>Priority</Label>
          <Select {...form.register('priority')}>
            <SelectItem value="low">Low</SelectItem>
            <SelectItem value="normal">Normal</SelectItem>
            <SelectItem value="high">High</SelectItem>
            <SelectItem value="urgent">Urgent</SelectItem>
          </Select>
        </div>
        <div>
          <Label>Scheduled Date</Label>
          <DatePicker {...form.register('scheduledDate')} />
        </div>
      </div>

      {/* Item Selection */}
      <Card>
        <CardHeader>
          <CardTitle>Items to Transfer</CardTitle>
        </CardHeader>
        <CardContent>
          {sourceId ? (
            <TransferItemSelector
              availableStock={sourceStock}
              selectedItems={items}
              onChange={setItems}
            />
          ) : (
            <p className="text-muted-foreground">Select source warehouse first</p>
          )}
        </CardContent>
      </Card>

      {/* Summary */}
      {items.length > 0 && (
        <Card>
          <CardContent className="pt-6">
            <div className="flex justify-between">
              <span>Total Items</span>
              <span>{items.reduce((sum, i) => sum + i.quantity, 0)}</span>
            </div>
            <div className="flex justify-between">
              <span>Total Value</span>
              <span>{formatCurrency(items.reduce((sum, i) => sum + i.quantity * i.unitCost, 0))}</span>
            </div>
          </CardContent>
        </Card>
      )}

      <div>
        <Label>Notes</Label>
        <Textarea {...form.register('notes')} />
      </div>

      <Button type="submit" className="w-full" disabled={items.length === 0}>
        Create Transfer Request
      </Button>
    </form>
  );
};
```

### TransferSuggestions

```tsx
const TransferSuggestions = () => {
  const { data: suggestions, isLoading } = useQuery({
    queryKey: ['transfer-suggestions'],
    queryFn: () => fetch('/api/transfers/suggestions').then(r => r.json())
  });

  const [selected, setSelected] = useState<Set<string>>(new Set());

  const createBulkTransfers = async () => {
    const selectedSuggestions = suggestions.filter(s =>
      selected.has(`${s.sourceWarehouseId}-${s.destinationWarehouseId}-${s.productId}`)
    );

    // Group by source-destination pair
    const grouped = groupBy(selectedSuggestions, s =>
      `${s.sourceWarehouseId}-${s.destinationWarehouseId}`
    );

    for (const [key, items] of Object.entries(grouped)) {
      const [sourceId, destId] = key.split('-');
      await createTransfer({
        sourceWarehouseId: sourceId,
        destinationWarehouseId: destId,
        type: 'rebalance',
        priority: items[0].priority,
        reason: 'sales_velocity',
        items: items.map(i => ({
          productId: i.productId,
          quantity: i.suggestedQty
        }))
      });
    }
  };

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle>Suggested Transfers</CardTitle>
        <Button
          onClick={createBulkTransfers}
          disabled={selected.size === 0}
        >
          Create {selected.size} Transfers
        </Button>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-12">
                <Checkbox
                  checked={selected.size === suggestions?.length}
                  onCheckedChange={(checked) => {
                    if (checked) {
                      setSelected(new Set(suggestions.map(s =>
                        `${s.sourceWarehouseId}-${s.destinationWarehouseId}-${s.productId}`
                      )));
                    } else {
                      setSelected(new Set());
                    }
                  }}
                />
              </TableHead>
              <TableHead>Product</TableHead>
              <TableHead>From</TableHead>
              <TableHead>To</TableHead>
              <TableHead className="text-right">Qty</TableHead>
              <TableHead>Reason</TableHead>
              <TableHead>Priority</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {suggestions?.map((s: TransferSuggestion) => {
              const key = `${s.sourceWarehouseId}-${s.destinationWarehouseId}-${s.productId}`;
              return (
                <TableRow key={key}>
                  <TableCell>
                    <Checkbox
                      checked={selected.has(key)}
                      onCheckedChange={(checked) => {
                        const newSet = new Set(selected);
                        if (checked) newSet.add(key);
                        else newSet.delete(key);
                        setSelected(newSet);
                      }}
                    />
                  </TableCell>
                  <TableCell>
                    <div>
                      <p className="font-medium">{s.productName}</p>
                      <p className="text-sm text-muted-foreground">{s.sku}</p>
                    </div>
                  </TableCell>
                  <TableCell>
                    <div>
                      <p>{s.sourceWarehouse}</p>
                      <p className="text-sm text-muted-foreground">Stock: {s.sourceStock}</p>
                    </div>
                  </TableCell>
                  <TableCell>
                    <div>
                      <p>{s.destinationWarehouse}</p>
                      <p className="text-sm text-muted-foreground">
                        Stock: {s.destStock} / ROP: {s.destReorderPoint}
                      </p>
                    </div>
                  </TableCell>
                  <TableCell className="text-right font-medium">
                    {s.suggestedQty}
                  </TableCell>
                  <TableCell>{s.reason}</TableCell>
                  <TableCell>
                    <PriorityBadge priority={s.priority} />
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
};
```
