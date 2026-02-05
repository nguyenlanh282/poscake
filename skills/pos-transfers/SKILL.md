---
name: pos-transfers
description: |
  Manage stock transfers between warehouses for POS systems: transfer requests (source/destination),
  approval workflow (manager approval), shipping/receiving (tracking, confirmation),
  transfer costing (FIFO, average cost), multi-location inventory sync, transfer analytics
  (frequency, lead time). Use when implementing multi-warehouse inventory, stock rebalancing,
  or building transfer management for retail chain POS.
version: 1.0.0
---

# POS Stock Transfers

Quản lý chuyển kho hàng hóa giữa các kho cho hệ thống POS.

## Transfer Features

### 1. Transfer Requests
Reference: [references/transfer-requests.md](references/transfer-requests.md)
- Create transfer from source to destination
- Item selection with quantity
- Priority levels (urgent, normal, low)
- Scheduled transfers

### 2. Approval Workflow
Reference: [references/approval-workflow.md](references/approval-workflow.md)
- Manager approval for high-value transfers
- Auto-approve for low-value
- Rejection with reasons

### 3. Shipping & Receiving
Reference: [references/shipping-receiving.md](references/shipping-receiving.md)
- Ship from source warehouse
- Transit tracking
- Receive at destination
- Discrepancy handling

### 4. Transfer Costing
Reference: [references/transfer-costing.md](references/transfer-costing.md)
- FIFO cost transfer
- Average cost method
- Transfer cost allocation

### 5. Transfer Analytics
Reference: [references/transfer-analytics.md](references/transfer-analytics.md)
- Transfer frequency by route
- Lead time analysis
- Cost analysis

## Data Models

```typescript
interface StockTransfer {
  id: string;
  transferNumber: string;     // TRF-2024-0001

  // Locations
  sourceWarehouseId: string;
  sourceWarehouse: string;
  destinationWarehouseId: string;
  destinationWarehouse: string;

  // Details
  status: TransferStatus;
  priority: TransferPriority;
  type: TransferType;

  // Items
  items: TransferItem[];
  totalQuantity: number;
  totalCost: number;

  // Dates
  requestedAt: Date;
  scheduledDate?: Date;
  approvedAt?: Date;
  shippedAt?: Date;
  receivedAt?: Date;
  completedAt?: Date;

  // Staff
  requestedBy: string;
  approvedBy?: string;
  shippedBy?: string;
  receivedBy?: string;

  // Tracking
  trackingNumber?: string;
  shippingMethod?: string;
  notes?: string;
}

type TransferStatus = 'draft' | 'pending' | 'approved' | 'rejected' | 'shipped' | 'in_transit' | 'received' | 'completed' | 'cancelled';
type TransferPriority = 'low' | 'normal' | 'high' | 'urgent';
type TransferType = 'rebalance' | 'replenishment' | 'consolidation' | 'emergency';

interface TransferItem {
  id: string;
  productId: string;
  productName: string;
  sku: string;
  variantName?: string;

  // Quantities
  requestedQty: number;
  shippedQty?: number;
  receivedQty?: number;

  // Cost
  unitCost: number;
  totalCost: number;

  // Stock levels (at time of request)
  sourceStock: number;
  destinationStock: number;

  // Discrepancy
  discrepancyQty?: number;
  discrepancyReason?: string;
}

interface TransferRoute {
  id: string;
  sourceWarehouseId: string;
  destinationWarehouseId: string;
  avgLeadTimeDays: number;
  shippingMethod: string;
  cost: number;
  isActive: boolean;
}
```

## Components

```
components/transfers/
├── TransferDashboard.tsx      # Transfers overview
├── CreateTransfer.tsx         # New transfer form
├── TransferItemSelector.tsx   # Select products to transfer
├── WarehouseSelector.tsx      # Source/destination picker
├── TransferApproval.tsx       # Approve/reject transfers
├── ShipTransfer.tsx           # Ship and add tracking
├── ReceiveTransfer.tsx        # Receive and confirm
├── DiscrepancyForm.tsx        # Handle discrepancies
├── TransferTimeline.tsx       # Status timeline
├── TransferHistory.tsx        # Transfer history
└── StockRebalance.tsx         # Auto-suggest rebalancing
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/transfers` | Create transfer |
| GET | `/api/transfers` | List transfers |
| GET | `/api/transfers/:id` | Transfer details |
| PUT | `/api/transfers/:id/approve` | Approve transfer |
| PUT | `/api/transfers/:id/reject` | Reject transfer |
| PUT | `/api/transfers/:id/ship` | Ship transfer |
| PUT | `/api/transfers/:id/receive` | Receive transfer |
| POST | `/api/transfers/:id/discrepancy` | Report discrepancy |
| GET | `/api/transfers/suggest` | Suggest rebalancing |
| GET | `/api/transfers/analytics` | Transfer analytics |

## Transfer Workflow

```typescript
const transferWorkflow = {
  steps: [
    { status: 'draft', label: 'Draft', description: 'Transfer created but not submitted' },
    { status: 'pending', label: 'Pending Approval', description: 'Awaiting manager approval' },
    { status: 'approved', label: 'Approved', description: 'Ready to ship' },
    { status: 'shipped', label: 'Shipped', description: 'Left source warehouse' },
    { status: 'in_transit', label: 'In Transit', description: 'On the way' },
    { status: 'received', label: 'Received', description: 'Arrived at destination' },
    { status: 'completed', label: 'Completed', description: 'Inventory updated' }
  ],

  approvalRules: {
    autoApprove: {
      enabled: true,
      maxValue: 10000000,     // Auto-approve under 10M VND
      maxItems: 50
    },
    requiredApprovers: {
      default: ['warehouse_manager'],
      highValue: ['warehouse_manager', 'operations_manager']  // Over 50M
    }
  }
};
```

## Stock Rebalancing

```typescript
interface RebalanceSuggestion {
  sourceWarehouseId: string;
  destinationWarehouseId: string;
  productId: string;
  suggestedQty: number;
  reason: RebalanceReason;
  priority: TransferPriority;
}

type RebalanceReason = 'low_stock' | 'overstock' | 'sales_velocity' | 'seasonal';

const calculateRebalancing = async (): Promise<RebalanceSuggestion[]> => {
  // Analyze stock levels across warehouses
  // Consider:
  // - Safety stock levels
  // - Sales velocity by location
  // - Lead time between warehouses
  // - Seasonal demand
  return suggestions;
};
```

## Discrepancy Handling

```typescript
const discrepancyReasons = [
  { code: 'damaged', label: 'Damaged in transit' },
  { code: 'lost', label: 'Lost in transit' },
  { code: 'short_ship', label: 'Short shipped from source' },
  { code: 'wrong_item', label: 'Wrong item received' },
  { code: 'count_error', label: 'Counting error' }
];

const handleDiscrepancy = async (
  transferId: string,
  item: TransferItem,
  actualQty: number,
  reason: string
) => {
  const discrepancy = item.shippedQty - actualQty;

  // Log discrepancy
  await createDiscrepancyRecord({
    transferId,
    itemId: item.id,
    expectedQty: item.shippedQty,
    actualQty,
    discrepancyQty: discrepancy,
    reason
  });

  // Update inventory accordingly
  if (reason === 'damaged') {
    await createDamageRecord(item.productId, discrepancy);
  }

  // Notify relevant parties
  await notifyDiscrepancy(transferId, item, discrepancy, reason);
};
```
