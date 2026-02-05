# Shipping & Receiving

Quy trình xuất kho và nhận hàng chuyển kho.

## Overview

Shipping và receiving quản lý việc xuất hàng từ source warehouse và nhận hàng tại destination warehouse.

## Shipping Process

```typescript
interface ShipmentData {
  transferId: string;
  transferNumber: string;

  // Shipping details
  carrier?: string;
  trackingNumber?: string;
  shippingMethod: ShippingMethod;
  estimatedArrival?: Date;

  // Packages
  packages: Package[];

  // Items
  pickedItems: PickedItem[];
  totalWeight: number;
  totalPackages: number;

  // Status
  status: ShipmentStatus;

  // Dates
  pickedAt?: Date;
  packedAt?: Date;
  shippedAt?: Date;
  deliveredAt?: Date;

  // Staff
  pickedBy?: string;
  packedBy?: string;
  shippedBy?: string;
}

type ShippingMethod = 'internal' | 'courier' | 'freight' | 'pickup';
type ShipmentStatus = 'picking' | 'picked' | 'packing' | 'packed' | 'shipped' | 'in_transit' | 'delivered';

interface Package {
  id: string;
  packageNumber: string;
  type: 'box' | 'pallet' | 'envelope';
  dimensions?: { length: number; width: number; height: number };
  weight: number;
  items: PackageItem[];
}

interface PackageItem {
  productId: string;
  sku: string;
  quantity: number;
}

interface PickedItem {
  transferItemId: string;
  productId: string;
  sku: string;
  requestedQty: number;
  pickedQty: number;
  location: string;           // Bin location
  lotNumber?: string;
  expiryDate?: Date;
}
```

## Service Implementation

```typescript
// services/transferShipping.ts

// Start picking process
export const startPicking = async (
  transferId: string,
  pickedBy: string
): Promise<TransferRequest> => {
  const transfer = await prisma.transferRequest.update({
    where: { id: transferId },
    data: {
      status: 'PICKING'
    },
    include: { items: true }
  });

  // Generate pick list with bin locations
  const pickList = await generatePickList(transfer);

  await prisma.pickList.create({
    data: {
      transferId,
      status: 'IN_PROGRESS',
      items: { create: pickList },
      startedAt: new Date(),
      pickedBy
    }
  });

  return transfer;
};

// Generate optimized pick list
const generatePickList = async (transfer: TransferRequest): Promise<PickListItem[]> => {
  const pickItems: PickListItem[] = [];

  for (const item of transfer.items) {
    // Get bin locations for this product
    const locations = await prisma.inventoryLocation.findMany({
      where: {
        warehouseId: transfer.sourceWarehouseId,
        productId: item.productId,
        quantity: { gt: 0 }
      },
      orderBy: [
        { expiryDate: 'asc' },  // FEFO
        { createdAt: 'asc' }    // FIFO
      ]
    });

    let remainingQty = item.requestedQty;

    for (const location of locations) {
      if (remainingQty <= 0) break;

      const pickQty = Math.min(remainingQty, location.quantity);

      pickItems.push({
        transferItemId: item.id,
        productId: item.productId,
        sku: item.sku,
        locationId: location.id,
        binCode: location.binCode,
        requestedQty: pickQty,
        lotNumber: location.lotNumber,
        expiryDate: location.expiryDate
      });

      remainingQty -= pickQty;
    }

    if (remainingQty > 0) {
      // Insufficient stock - should have been caught earlier
      throw new Error(`Insufficient stock for ${item.sku}`);
    }
  }

  // Optimize pick route (sort by bin location)
  return pickItems.sort((a, b) => a.binCode.localeCompare(b.binCode));
};

// Complete picking
export const completePicking = async (
  transferId: string,
  pickedItems: { pickItemId: string; pickedQty: number }[],
  pickedBy: string
): Promise<TransferRequest> => {
  // Update pick list items
  for (const item of pickedItems) {
    await prisma.pickListItem.update({
      where: { id: item.pickItemId },
      data: {
        pickedQty: item.pickedQty,
        status: 'PICKED'
      }
    });
  }

  // Update transfer items with picked quantities
  const groupedByTransferItem = groupBy(pickedItems, 'transferItemId');
  for (const [transferItemId, items] of Object.entries(groupedByTransferItem)) {
    const totalPicked = items.reduce((sum, i) => sum + i.pickedQty, 0);
    await prisma.transferItem.update({
      where: { id: transferItemId },
      data: {
        pickedQty: totalPicked,
        status: 'PICKED'
      }
    });
  }

  // Deduct from source inventory
  await deductSourceInventory(transferId, pickedItems);

  // Update transfer status
  return await prisma.transferRequest.update({
    where: { id: transferId },
    data: { status: 'PICKED' }
  });
};

// Ship transfer
export const shipTransfer = async (
  transferId: string,
  shippingData: {
    carrier?: string;
    trackingNumber?: string;
    shippingMethod: ShippingMethod;
    packages: Package[];
    estimatedArrival?: Date;
  },
  shippedBy: string
): Promise<TransferRequest> => {
  // Create shipment record
  await prisma.shipment.create({
    data: {
      transferId,
      carrier: shippingData.carrier,
      trackingNumber: shippingData.trackingNumber,
      shippingMethod: shippingData.shippingMethod,
      estimatedArrival: shippingData.estimatedArrival,
      packages: { create: shippingData.packages },
      totalPackages: shippingData.packages.length,
      totalWeight: shippingData.packages.reduce((sum, p) => sum + p.weight, 0),
      shippedBy,
      shippedAt: new Date(),
      status: 'SHIPPED'
    }
  });

  // Update transfer items
  await prisma.transferItem.updateMany({
    where: { transferId },
    data: { status: 'SHIPPED' }
  });

  // Update transfer status
  const transfer = await prisma.transferRequest.update({
    where: { id: transferId },
    data: { status: 'SHIPPED' }
  });

  // Notify destination warehouse
  await notifyShipment(transfer);

  return transfer;
};
```

## Receiving Process

```typescript
interface ReceivingData {
  transferId: string;
  receivedItems: ReceivedItem[];
  receivedBy: string;
  receivedAt: Date;
  notes?: string;
}

interface ReceivedItem {
  transferItemId: string;
  receivedQty: number;
  condition: 'good' | 'damaged' | 'missing';
  notes?: string;
  binLocation?: string;
}

interface Discrepancy {
  transferItemId: string;
  productId: string;
  sku: string;
  expectedQty: number;
  receivedQty: number;
  variance: number;
  reason: DiscrepancyReason;
  notes?: string;
}

type DiscrepancyReason = 'short_ship' | 'over_ship' | 'damaged' | 'wrong_item' | 'lost' | 'count_error';

// Receive transfer
export const receiveTransfer = async (
  transferId: string,
  receivedItems: ReceivedItem[],
  receivedBy: string
): Promise<TransferRequest> => {
  const transfer = await prisma.transferRequest.findUnique({
    where: { id: transferId },
    include: { items: true }
  });

  const discrepancies: Discrepancy[] = [];

  // Process each received item
  for (const received of receivedItems) {
    const transferItem = transfer.items.find(i => i.id === received.transferItemId);
    const expectedQty = transferItem.shippedQty;

    // Check for discrepancy
    if (received.receivedQty !== expectedQty) {
      discrepancies.push({
        transferItemId: received.transferItemId,
        productId: transferItem.productId,
        sku: transferItem.sku,
        expectedQty,
        receivedQty: received.receivedQty,
        variance: received.receivedQty - expectedQty,
        reason: received.receivedQty < expectedQty ? 'short_ship' : 'over_ship',
        notes: received.notes
      });
    }

    // Update transfer item
    await prisma.transferItem.update({
      where: { id: received.transferItemId },
      data: {
        receivedQty: received.receivedQty,
        status: received.condition === 'good' ? 'RECEIVED' : 'DISCREPANCY'
      }
    });

    // Add to destination inventory (only good condition)
    if (received.condition === 'good' && received.receivedQty > 0) {
      await addToDestinationInventory(
        transfer.destinationWarehouseId,
        transferItem.productId,
        received.receivedQty,
        received.binLocation
      );
    }

    // Handle damaged items
    if (received.condition === 'damaged') {
      await createDamageRecord({
        transferId,
        productId: transferItem.productId,
        quantity: received.receivedQty,
        notes: received.notes
      });
    }
  }

  // Create discrepancy records if any
  if (discrepancies.length > 0) {
    await prisma.transferDiscrepancy.createMany({
      data: discrepancies.map(d => ({
        transferId,
        ...d,
        status: 'PENDING'
      }))
    });

    // Notify source warehouse
    await notifyDiscrepancies(transfer, discrepancies);
  }

  // Update transfer status
  const status = discrepancies.length > 0 ? 'RECEIVED' : 'COMPLETED';

  return await prisma.transferRequest.update({
    where: { id: transferId },
    data: {
      status,
      receivedAt: new Date()
    }
  });
};
```

## Components

### PickingList

```tsx
const PickingList = ({ transfer }: { transfer: TransferRequest }) => {
  const { data: pickList } = useQuery({
    queryKey: ['pick-list', transfer.id],
    queryFn: () => fetch(`/api/transfers/${transfer.id}/pick-list`).then(r => r.json())
  });

  const [pickedItems, setPickedItems] = useState<Map<string, number>>(new Map());

  const handlePick = (itemId: string, qty: number) => {
    setPickedItems(new Map(pickedItems.set(itemId, qty)));
  };

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-bold">Pick List</h2>
        <Badge variant={pickList?.status === 'IN_PROGRESS' ? 'default' : 'secondary'}>
          {pickList?.status}
        </Badge>
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Location</TableHead>
            <TableHead>Product</TableHead>
            <TableHead>SKU</TableHead>
            <TableHead>Lot</TableHead>
            <TableHead className="text-right">Required</TableHead>
            <TableHead className="text-right">Picked</TableHead>
            <TableHead></TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {pickList?.items.map((item: PickListItem) => (
            <TableRow key={item.id}>
              <TableCell className="font-mono font-bold">
                {item.binCode}
              </TableCell>
              <TableCell>{item.productName}</TableCell>
              <TableCell>{item.sku}</TableCell>
              <TableCell>
                {item.lotNumber}
                {item.expiryDate && (
                  <span className="text-sm text-muted-foreground ml-2">
                    Exp: {formatDate(item.expiryDate)}
                  </span>
                )}
              </TableCell>
              <TableCell className="text-right">{item.requestedQty}</TableCell>
              <TableCell className="text-right">
                <Input
                  type="number"
                  value={pickedItems.get(item.id) ?? ''}
                  onChange={(e) => handlePick(item.id, parseInt(e.target.value))}
                  className="w-20 text-right"
                  max={item.requestedQty}
                />
              </TableCell>
              <TableCell>
                <Button
                  size="sm"
                  variant={pickedItems.get(item.id) === item.requestedQty ? 'default' : 'outline'}
                  onClick={() => handlePick(item.id, item.requestedQty)}
                >
                  <Check className="h-4 w-4" />
                </Button>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>

      <Button
        onClick={() => completePicking(transfer.id, Array.from(pickedItems.entries()))}
        disabled={pickedItems.size !== pickList?.items.length}
        className="w-full"
      >
        Complete Picking
      </Button>
    </div>
  );
};
```

### ReceivingForm

```tsx
const ReceivingForm = ({ transfer }: { transfer: TransferRequest }) => {
  const [receivedItems, setReceivedItems] = useState<Map<string, ReceivedItem>>(new Map());

  const updateItem = (itemId: string, data: Partial<ReceivedItem>) => {
    const current = receivedItems.get(itemId) || {
      transferItemId: itemId,
      receivedQty: 0,
      condition: 'good'
    };
    setReceivedItems(new Map(receivedItems.set(itemId, { ...current, ...data })));
  };

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-bold">Receive Transfer</h2>
        <span className="text-muted-foreground">
          {transfer.transferNumber}
        </span>
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Product</TableHead>
            <TableHead>SKU</TableHead>
            <TableHead className="text-right">Expected</TableHead>
            <TableHead className="text-right">Received</TableHead>
            <TableHead>Condition</TableHead>
            <TableHead>Bin Location</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {transfer.items.map((item) => (
            <TableRow key={item.id}>
              <TableCell>{item.productName}</TableCell>
              <TableCell>{item.sku}</TableCell>
              <TableCell className="text-right">{item.shippedQty}</TableCell>
              <TableCell className="text-right">
                <Input
                  type="number"
                  value={receivedItems.get(item.id)?.receivedQty ?? ''}
                  onChange={(e) => updateItem(item.id, {
                    receivedQty: parseInt(e.target.value)
                  })}
                  className="w-20 text-right"
                />
              </TableCell>
              <TableCell>
                <Select
                  value={receivedItems.get(item.id)?.condition ?? 'good'}
                  onValueChange={(v) => updateItem(item.id, { condition: v as any })}
                >
                  <SelectItem value="good">Good</SelectItem>
                  <SelectItem value="damaged">Damaged</SelectItem>
                  <SelectItem value="missing">Missing</SelectItem>
                </Select>
              </TableCell>
              <TableCell>
                <Input
                  placeholder="Bin location"
                  value={receivedItems.get(item.id)?.binLocation ?? ''}
                  onChange={(e) => updateItem(item.id, { binLocation: e.target.value })}
                  className="w-24"
                />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>

      {/* Discrepancy summary */}
      {hasDiscrepancies(receivedItems, transfer.items) && (
        <Alert variant="warning">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>
            Quantities don't match. Discrepancy report will be created.
          </AlertDescription>
        </Alert>
      )}

      <Button
        onClick={() => receiveTransfer(transfer.id, Array.from(receivedItems.values()))}
        disabled={receivedItems.size !== transfer.items.length}
        className="w-full"
      >
        Complete Receiving
      </Button>
    </div>
  );
};
```
