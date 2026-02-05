# Transfer Costing

Quản lý chi phí và tính giá vốn khi chuyển kho.

## Overview

Transfer costing xác định cách tính giá vốn hàng hóa khi di chuyển giữa các warehouse - FIFO, LIFO, hoặc average cost.

## Costing Methods

```typescript
type CostingMethod = 'fifo' | 'lifo' | 'average' | 'specific';

interface TransferCostConfig {
  costingMethod: CostingMethod;
  includeTransferCosts: boolean;   // Add shipping/handling to cost
  trackByLot: boolean;             // Track cost by lot number
  allowNegativeMargin: boolean;
}

interface ItemCost {
  productId: string;
  quantity: number;
  unitCost: number;
  totalCost: number;
  lotNumber?: string;
  costLayers?: CostLayer[];        // For FIFO/LIFO
}

interface CostLayer {
  layerId: string;
  quantity: number;
  unitCost: number;
  receivedDate: Date;
  lotNumber?: string;
  expiryDate?: Date;
}

interface TransferCost {
  transferId: string;

  // Item costs
  itemsCost: number;

  // Additional costs
  shippingCost: number;
  handlingCost: number;
  insuranceCost: number;
  otherCosts: number;

  // Total
  totalCost: number;

  // Allocated (per item)
  allocationMethod: 'value' | 'quantity' | 'weight';
  allocatedCosts: AllocatedCost[];
}

interface AllocatedCost {
  itemId: string;
  itemCost: number;
  allocatedOverhead: number;
  totalUnitCost: number;
  totalLineCost: number;
}
```

## FIFO Costing

```typescript
// services/transferCosting.ts

export const calculateFIFOCost = async (
  productId: string,
  warehouseId: string,
  quantity: number
): Promise<ItemCost> => {
  // Get cost layers ordered by date (oldest first)
  const layers = await prisma.costLayer.findMany({
    where: {
      productId,
      warehouseId,
      remainingQty: { gt: 0 }
    },
    orderBy: { receivedDate: 'asc' }
  });

  const usedLayers: CostLayer[] = [];
  let remainingQty = quantity;
  let totalCost = 0;

  for (const layer of layers) {
    if (remainingQty <= 0) break;

    const qtyFromLayer = Math.min(remainingQty, layer.remainingQty);
    totalCost += qtyFromLayer * layer.unitCost;
    remainingQty -= qtyFromLayer;

    usedLayers.push({
      layerId: layer.id,
      quantity: qtyFromLayer,
      unitCost: layer.unitCost,
      receivedDate: layer.receivedDate,
      lotNumber: layer.lotNumber
    });
  }

  if (remainingQty > 0) {
    throw new Error(`Insufficient cost layers for ${quantity} units`);
  }

  return {
    productId,
    quantity,
    unitCost: totalCost / quantity,
    totalCost,
    costLayers: usedLayers
  };
};

// Consume FIFO layers after transfer ships
export const consumeFIFOLayers = async (
  itemCost: ItemCost,
  warehouseId: string
) => {
  for (const layer of itemCost.costLayers || []) {
    await prisma.costLayer.update({
      where: { id: layer.layerId },
      data: {
        remainingQty: { decrement: layer.quantity }
      }
    });

    // Record layer consumption
    await prisma.costLayerMovement.create({
      data: {
        layerId: layer.layerId,
        type: 'TRANSFER_OUT',
        quantity: layer.quantity,
        warehouseId
      }
    });
  }
};

// Create new cost layers at destination
export const createDestinationLayers = async (
  transferId: string,
  destinationWarehouseId: string,
  itemCosts: ItemCost[],
  overheadAllocation: AllocatedCost[]
) => {
  for (const itemCost of itemCosts) {
    const allocation = overheadAllocation.find(a => a.itemId === itemCost.productId);
    const adjustedUnitCost = allocation
      ? allocation.totalUnitCost
      : itemCost.unitCost;

    // Create new cost layer at destination
    await prisma.costLayer.create({
      data: {
        productId: itemCost.productId,
        warehouseId: destinationWarehouseId,
        quantity: itemCost.quantity,
        remainingQty: itemCost.quantity,
        unitCost: adjustedUnitCost,
        receivedDate: new Date(),
        lotNumber: itemCost.lotNumber,
        sourceType: 'TRANSFER',
        sourceId: transferId
      }
    });
  }
};
```

## Average Cost

```typescript
export const calculateAverageCost = async (
  productId: string,
  warehouseId: string,
  quantity: number
): Promise<ItemCost> => {
  const inventory = await prisma.inventoryCost.findUnique({
    where: {
      productId_warehouseId: { productId, warehouseId }
    }
  });

  if (!inventory || inventory.quantity < quantity) {
    throw new Error('Insufficient inventory');
  }

  const unitCost = inventory.averageCost;
  const totalCost = unitCost * quantity;

  return {
    productId,
    quantity,
    unitCost,
    totalCost
  };
};

// Update weighted average after receiving
export const updateWeightedAverage = async (
  productId: string,
  warehouseId: string,
  receivedQty: number,
  receivedUnitCost: number
) => {
  const current = await prisma.inventoryCost.findUnique({
    where: {
      productId_warehouseId: { productId, warehouseId }
    }
  });

  const currentQty = current?.quantity || 0;
  const currentCost = current?.averageCost || 0;

  const newTotalQty = currentQty + receivedQty;
  const newTotalCost = (currentQty * currentCost) + (receivedQty * receivedUnitCost);
  const newAverageCost = newTotalCost / newTotalQty;

  await prisma.inventoryCost.upsert({
    where: {
      productId_warehouseId: { productId, warehouseId }
    },
    update: {
      quantity: newTotalQty,
      averageCost: newAverageCost,
      totalCost: newTotalCost
    },
    create: {
      productId,
      warehouseId,
      quantity: newTotalQty,
      averageCost: newAverageCost,
      totalCost: newTotalCost
    }
  });
};
```

## Overhead Allocation

```typescript
interface OverheadCosts {
  shipping: number;
  handling: number;
  insurance: number;
  other: number;
  total: number;
}

export const allocateOverheadCosts = (
  items: TransferItem[],
  overhead: OverheadCosts,
  method: 'value' | 'quantity' | 'weight'
): AllocatedCost[] => {
  // Calculate allocation base
  let totalBase: number;
  const itemBases: Map<string, number> = new Map();

  switch (method) {
    case 'value':
      totalBase = items.reduce((sum, i) => sum + i.totalCost, 0);
      items.forEach(i => itemBases.set(i.id, i.totalCost));
      break;

    case 'quantity':
      totalBase = items.reduce((sum, i) => sum + i.requestedQty, 0);
      items.forEach(i => itemBases.set(i.id, i.requestedQty));
      break;

    case 'weight':
      totalBase = items.reduce((sum, i) => sum + (i.weight || 0), 0);
      items.forEach(i => itemBases.set(i.id, i.weight || 0));
      break;
  }

  // Allocate to each item
  return items.map(item => {
    const base = itemBases.get(item.id) || 0;
    const allocationRatio = totalBase > 0 ? base / totalBase : 0;
    const allocatedOverhead = overhead.total * allocationRatio;

    const totalLineCost = item.totalCost + allocatedOverhead;
    const totalUnitCost = item.requestedQty > 0
      ? totalLineCost / item.requestedQty
      : item.unitCost;

    return {
      itemId: item.id,
      itemCost: item.totalCost,
      allocatedOverhead,
      totalUnitCost,
      totalLineCost
    };
  });
};
```

## Cost Variance Report

```typescript
interface CostVariance {
  transferId: string;
  transferNumber: string;
  itemId: string;
  productName: string;

  // Expected cost (at source)
  expectedUnitCost: number;
  expectedTotalCost: number;

  // Actual cost (including overhead)
  actualUnitCost: number;
  actualTotalCost: number;

  // Variance
  unitVariance: number;
  totalVariance: number;
  variancePercent: number;
}

export const calculateCostVariance = async (
  transferId: string
): Promise<CostVariance[]> => {
  const transfer = await prisma.transferRequest.findUnique({
    where: { id: transferId },
    include: {
      items: true,
      costAllocation: { include: { allocatedCosts: true } }
    }
  });

  return transfer.items.map(item => {
    const allocation = transfer.costAllocation?.allocatedCosts.find(
      a => a.itemId === item.id
    );

    const expectedTotalCost = item.unitCost * item.receivedQty;
    const actualTotalCost = allocation?.totalLineCost || expectedTotalCost;

    const unitVariance = (allocation?.totalUnitCost || item.unitCost) - item.unitCost;
    const totalVariance = actualTotalCost - expectedTotalCost;

    return {
      transferId,
      transferNumber: transfer.transferNumber,
      itemId: item.id,
      productName: item.productName,
      expectedUnitCost: item.unitCost,
      expectedTotalCost,
      actualUnitCost: allocation?.totalUnitCost || item.unitCost,
      actualTotalCost,
      unitVariance,
      totalVariance,
      variancePercent: expectedTotalCost > 0
        ? (totalVariance / expectedTotalCost) * 100
        : 0
    };
  });
};
```

## Components

### TransferCostSummary

```tsx
const TransferCostSummary = ({ transfer }: { transfer: TransferRequest }) => {
  const { data: costs } = useQuery({
    queryKey: ['transfer-costs', transfer.id],
    queryFn: () => fetch(`/api/transfers/${transfer.id}/costs`).then(r => r.json())
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Cost Summary</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Items cost */}
        <div className="flex justify-between">
          <span>Items Cost</span>
          <span>{formatCurrency(costs?.itemsCost)}</span>
        </div>

        {/* Overhead */}
        {costs?.shippingCost > 0 && (
          <div className="flex justify-between text-muted-foreground">
            <span className="pl-4">Shipping</span>
            <span>{formatCurrency(costs.shippingCost)}</span>
          </div>
        )}
        {costs?.handlingCost > 0 && (
          <div className="flex justify-between text-muted-foreground">
            <span className="pl-4">Handling</span>
            <span>{formatCurrency(costs.handlingCost)}</span>
          </div>
        )}
        {costs?.insuranceCost > 0 && (
          <div className="flex justify-between text-muted-foreground">
            <span className="pl-4">Insurance</span>
            <span>{formatCurrency(costs.insuranceCost)}</span>
          </div>
        )}

        <Separator />

        {/* Total */}
        <div className="flex justify-between font-bold">
          <span>Total Cost</span>
          <span>{formatCurrency(costs?.totalCost)}</span>
        </div>

        {/* Per item breakdown */}
        <Accordion type="single" collapsible>
          <AccordionItem value="breakdown">
            <AccordionTrigger>View Item Breakdown</AccordionTrigger>
            <AccordionContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Product</TableHead>
                    <TableHead className="text-right">Item Cost</TableHead>
                    <TableHead className="text-right">Allocated</TableHead>
                    <TableHead className="text-right">Total/Unit</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {costs?.allocatedCosts.map((cost: AllocatedCost) => (
                    <TableRow key={cost.itemId}>
                      <TableCell>{cost.productName}</TableCell>
                      <TableCell className="text-right">
                        {formatCurrency(cost.itemCost)}
                      </TableCell>
                      <TableCell className="text-right">
                        {formatCurrency(cost.allocatedOverhead)}
                      </TableCell>
                      <TableCell className="text-right">
                        {formatCurrency(cost.totalUnitCost)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </AccordionContent>
          </AccordionItem>
        </Accordion>
      </CardContent>
    </Card>
  );
};
```

### CostLayerVisualization

```tsx
const CostLayerVisualization = ({ productId, warehouseId }: { productId: string; warehouseId: string }) => {
  const { data: layers } = useQuery({
    queryKey: ['cost-layers', productId, warehouseId],
    queryFn: () => fetch(`/api/inventory/cost-layers?product=${productId}&warehouse=${warehouseId}`).then(r => r.json())
  });

  return (
    <div className="space-y-2">
      {layers?.map((layer: CostLayer, index: number) => (
        <div
          key={layer.layerId}
          className="flex items-center gap-4 p-3 border rounded"
        >
          <Badge variant={index === 0 ? 'default' : 'secondary'}>
            {index === 0 ? 'FIFO Next' : `Layer ${index + 1}`}
          </Badge>
          <div className="flex-1">
            <p className="text-sm font-medium">
              {layer.quantity} units @ {formatCurrency(layer.unitCost)}
            </p>
            <p className="text-xs text-muted-foreground">
              Received: {formatDate(layer.receivedDate)}
              {layer.lotNumber && ` • Lot: ${layer.lotNumber}`}
            </p>
          </div>
          <p className="font-mono">{formatCurrency(layer.quantity * layer.unitCost)}</p>
        </div>
      ))}
    </div>
  );
};
```
