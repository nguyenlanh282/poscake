# Approval Workflow

Quy trình phê duyệt chuyển kho dựa trên giá trị và quy định.

## Overview

Approval workflow đảm bảo các transfer requests được review và phê duyệt đúng người trước khi thực hiện.

## Configuration

```typescript
interface ApprovalConfig {
  // Auto-approval settings
  autoApprove: {
    enabled: boolean;
    maxValue: number;           // Max value for auto-approve
    maxItems: number;           // Max items for auto-approve
    maxQuantity: number;        // Max total quantity
    excludedTypes: TransferType[];
  };

  // Approval levels
  levels: ApprovalLevel[];

  // Escalation
  escalation: {
    reminderAfterHours: number;
    escalateAfterHours: number;
    maxEscalationLevel: number;
  };
}

interface ApprovalLevel {
  id: string;
  name: string;
  minValue: number;
  maxValue: number;
  requiredApprovers: string[];  // Roles
  requiredCount: number;        // How many approvals needed
  canDelegate: boolean;
}

// Default configuration
const defaultApprovalConfig: ApprovalConfig = {
  autoApprove: {
    enabled: true,
    maxValue: 10000000,         // 10M VND
    maxItems: 50,
    maxQuantity: 100,
    excludedTypes: ['emergency']
  },

  levels: [
    {
      id: 'level1',
      name: 'Warehouse Manager',
      minValue: 0,
      maxValue: 50000000,
      requiredApprovers: ['warehouse_manager'],
      requiredCount: 1,
      canDelegate: true
    },
    {
      id: 'level2',
      name: 'Operations Manager',
      minValue: 50000000,
      maxValue: 200000000,
      requiredApprovers: ['operations_manager', 'warehouse_manager'],
      requiredCount: 1,
      canDelegate: true
    },
    {
      id: 'level3',
      name: 'Director Approval',
      minValue: 200000000,
      maxValue: Infinity,
      requiredApprovers: ['director', 'cfo'],
      requiredCount: 2,
      canDelegate: false
    }
  ],

  escalation: {
    reminderAfterHours: 24,
    escalateAfterHours: 48,
    maxEscalationLevel: 2
  }
};
```

## Data Model

```typescript
interface TransferApproval {
  id: string;
  transferId: string;

  // Approval level
  levelId: string;
  levelName: string;
  requiredCount: number;

  // Status
  status: ApprovalStatus;

  // Approvers
  approvals: ApproverAction[];
  pendingApprovers: string[];

  // Dates
  requestedAt: Date;
  completedAt?: Date;
  escalatedAt?: Date;

  // Escalation
  escalationLevel: number;
  escalatedTo?: string;
}

interface ApproverAction {
  id: string;
  approverId: string;
  approverName: string;
  approverRole: string;
  action: 'approve' | 'reject';
  notes?: string;
  actedAt: Date;
}

type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'escalated' | 'expired';
```

## Service Implementation

```typescript
// services/transferApproval.ts

// Initiate approval process
export const initiateApproval = async (
  transferId: string
): Promise<TransferApproval> => {
  const transfer = await prisma.transferRequest.findUnique({
    where: { id: transferId }
  });

  const config = await getApprovalConfig();
  const level = determineApprovalLevel(transfer.totalCost, config);

  const pendingApprovers = await getEligibleApprovers(level.requiredApprovers);

  const approval = await prisma.transferApproval.create({
    data: {
      transferId,
      levelId: level.id,
      levelName: level.name,
      requiredCount: level.requiredCount,
      status: 'PENDING',
      pendingApprovers: pendingApprovers.map(a => a.id),
      requestedAt: new Date(),
      escalationLevel: 0
    }
  });

  // Notify approvers
  await notifyApprovers(pendingApprovers, transfer, approval);

  // Schedule reminder
  await scheduleReminder(approval.id, config.escalation.reminderAfterHours);

  return approval;
};

// Approve transfer
export const approveTransfer = async (
  transferId: string,
  approverId: string,
  notes?: string
): Promise<TransferRequest> => {
  const approval = await prisma.transferApproval.findFirst({
    where: { transferId, status: 'PENDING' },
    include: { approvals: true }
  });

  if (!approval) {
    throw new Error('No pending approval found');
  }

  const approver = await prisma.user.findUnique({
    where: { id: approverId }
  });

  // Check if user can approve
  if (!approval.pendingApprovers.includes(approverId)) {
    throw new Error('User not authorized to approve this transfer');
  }

  // Record approval action
  await prisma.approverAction.create({
    data: {
      approvalId: approval.id,
      approverId,
      approverName: approver.name,
      approverRole: approver.role,
      action: 'APPROVE',
      notes,
      actedAt: new Date()
    }
  });

  const totalApprovals = approval.approvals.filter(a => a.action === 'APPROVE').length + 1;

  // Check if enough approvals
  if (totalApprovals >= approval.requiredCount) {
    // Fully approved
    await prisma.transferApproval.update({
      where: { id: approval.id },
      data: {
        status: 'APPROVED',
        completedAt: new Date()
      }
    });

    // Update transfer status
    const transfer = await prisma.transferRequest.update({
      where: { id: transferId },
      data: {
        status: 'APPROVED',
        approvedBy: approverId
      }
    });

    // Notify requester
    await notifyApprovalComplete(transfer);

    return transfer;
  }

  // Still pending more approvals
  return await prisma.transferRequest.findUnique({
    where: { id: transferId }
  });
};

// Reject transfer
export const rejectTransfer = async (
  transferId: string,
  approverId: string,
  reason: string
): Promise<TransferRequest> => {
  const approval = await prisma.transferApproval.findFirst({
    where: { transferId, status: 'PENDING' }
  });

  const approver = await prisma.user.findUnique({
    where: { id: approverId }
  });

  // Record rejection
  await prisma.approverAction.create({
    data: {
      approvalId: approval.id,
      approverId,
      approverName: approver.name,
      approverRole: approver.role,
      action: 'REJECT',
      notes: reason,
      actedAt: new Date()
    }
  });

  // Update approval status
  await prisma.transferApproval.update({
    where: { id: approval.id },
    data: {
      status: 'REJECTED',
      completedAt: new Date()
    }
  });

  // Update transfer
  const transfer = await prisma.transferRequest.update({
    where: { id: transferId },
    data: { status: 'REJECTED' }
  });

  // Release reserved stock
  await releaseReservedStock(transferId);

  // Notify requester
  await notifyRejection(transfer, reason);

  return transfer;
};

// Escalate pending approval
export const escalateApproval = async (approvalId: string) => {
  const approval = await prisma.transferApproval.findUnique({
    where: { id: approvalId },
    include: { transfer: true }
  });

  const config = await getApprovalConfig();

  if (approval.escalationLevel >= config.escalation.maxEscalationLevel) {
    // Max escalation reached - notify admin
    await notifyAdminEscalation(approval);
    return;
  }

  // Get next level approvers
  const currentLevel = config.levels.find(l => l.id === approval.levelId);
  const nextLevelIndex = config.levels.indexOf(currentLevel) + 1;

  if (nextLevelIndex >= config.levels.length) {
    await notifyAdminEscalation(approval);
    return;
  }

  const nextLevel = config.levels[nextLevelIndex];
  const escalatedApprovers = await getEligibleApprovers(nextLevel.requiredApprovers);

  await prisma.transferApproval.update({
    where: { id: approvalId },
    data: {
      status: 'ESCALATED',
      escalationLevel: approval.escalationLevel + 1,
      escalatedAt: new Date(),
      escalatedTo: escalatedApprovers[0].id,
      pendingApprovers: escalatedApprovers.map(a => a.id)
    }
  });

  // Notify escalated approvers
  await notifyEscalation(escalatedApprovers, approval.transfer, approval);
};
```

## Delegation

```typescript
interface ApprovalDelegation {
  id: string;
  delegatorId: string;
  delegateeId: string;
  transferTypes?: TransferType[];
  maxValue?: number;
  startDate: Date;
  endDate: Date;
  reason: string;
  status: 'active' | 'expired' | 'revoked';
}

export const createDelegation = async (
  delegatorId: string,
  data: CreateDelegationInput
): Promise<ApprovalDelegation> => {
  // Validate delegator can delegate
  const config = await getApprovalConfig();
  const delegatorRole = await getUserRole(delegatorId);

  const canDelegate = config.levels.some(
    l => l.requiredApprovers.includes(delegatorRole) && l.canDelegate
  );

  if (!canDelegate) {
    throw new Error('User cannot delegate approval authority');
  }

  return await prisma.approvalDelegation.create({
    data: {
      delegatorId,
      delegateeId: data.delegateeId,
      transferTypes: data.transferTypes,
      maxValue: data.maxValue,
      startDate: data.startDate,
      endDate: data.endDate,
      reason: data.reason,
      status: 'ACTIVE'
    }
  });
};
```

## Components

### ApprovalActions

```tsx
const ApprovalActions = ({ transfer, approval }: ApprovalActionsProps) => {
  const { user } = useAuth();
  const canApprove = approval.pendingApprovers.includes(user.id);

  const [rejectReason, setRejectReason] = useState('');
  const [showRejectDialog, setShowRejectDialog] = useState(false);

  const { mutate: approve, isLoading: approving } = useMutation({
    mutationFn: () => fetch(`/api/transfers/${transfer.id}/approve`, { method: 'POST' })
  });

  const { mutate: reject, isLoading: rejecting } = useMutation({
    mutationFn: () => fetch(`/api/transfers/${transfer.id}/reject`, {
      method: 'POST',
      body: JSON.stringify({ reason: rejectReason })
    })
  });

  if (!canApprove) {
    return (
      <Alert>
        <AlertDescription>
          Waiting for approval from: {approval.pendingApprovers.join(', ')}
        </AlertDescription>
      </Alert>
    );
  }

  return (
    <div className="flex gap-4">
      <Button
        onClick={() => approve()}
        disabled={approving}
        className="flex-1"
      >
        <Check className="h-4 w-4 mr-2" />
        Approve
      </Button>

      <Button
        variant="destructive"
        onClick={() => setShowRejectDialog(true)}
        className="flex-1"
      >
        <X className="h-4 w-4 mr-2" />
        Reject
      </Button>

      <Dialog open={showRejectDialog} onOpenChange={setShowRejectDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reject Transfer</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Reason for rejection</Label>
              <Textarea
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder="Explain why this transfer is rejected..."
              />
            </div>
            <div className="flex gap-2 justify-end">
              <Button variant="outline" onClick={() => setShowRejectDialog(false)}>
                Cancel
              </Button>
              <Button
                variant="destructive"
                onClick={() => reject()}
                disabled={!rejectReason || rejecting}
              >
                Confirm Rejection
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};
```

### ApprovalTimeline

```tsx
const ApprovalTimeline = ({ approval }: { approval: TransferApproval }) => (
  <div className="space-y-4">
    {/* Request submitted */}
    <TimelineItem
      icon={FileText}
      title="Request Submitted"
      description={`Level: ${approval.levelName}`}
      date={approval.requestedAt}
      status="completed"
    />

    {/* Approval actions */}
    {approval.approvals.map((action) => (
      <TimelineItem
        key={action.id}
        icon={action.action === 'approve' ? Check : X}
        title={`${action.action === 'approve' ? 'Approved' : 'Rejected'} by ${action.approverName}`}
        description={action.notes}
        date={action.actedAt}
        status={action.action === 'approve' ? 'success' : 'error'}
      />
    ))}

    {/* Escalation */}
    {approval.escalatedAt && (
      <TimelineItem
        icon={ArrowUp}
        title="Escalated"
        description={`Escalated to ${approval.escalatedTo}`}
        date={approval.escalatedAt}
        status="warning"
      />
    )}

    {/* Pending */}
    {approval.status === 'pending' && (
      <TimelineItem
        icon={Clock}
        title="Awaiting Approval"
        description={`${approval.requiredCount - approval.approvals.length} more approval(s) needed`}
        status="pending"
      />
    )}

    {/* Completed */}
    {approval.completedAt && (
      <TimelineItem
        icon={CheckCircle}
        title={approval.status === 'approved' ? 'Approved' : 'Completed'}
        date={approval.completedAt}
        status={approval.status === 'approved' ? 'success' : 'completed'}
      />
    )}
  </div>
);
```
