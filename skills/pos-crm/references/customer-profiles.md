# Customer Profiles

Quản lý thông tin chi tiết khách hàng trong CRM.

## Overview

Customer profiles lưu trữ đầy đủ thông tin khách hàng bao gồm lịch sử mua hàng, preferences, notes và communication history.

## Data Model

```typescript
interface CustomerProfile {
  id: string;
  code: string;              // Customer code: KH0001

  // Basic info
  name: string;
  email?: string;
  phone: string;
  dateOfBirth?: Date;
  gender?: 'male' | 'female' | 'other';
  avatar?: string;

  // Address
  addresses: CustomerAddress[];
  defaultAddressId?: string;

  // CRM data
  segment: CustomerSegment;
  loyaltyTier: LoyaltyTier;
  loyaltyPoints: number;
  lifetimeValue: number;
  orderCount: number;
  lastOrderAt?: Date;

  // Preferences
  preferredChannel: CommunicationChannel;
  marketingConsent: boolean;
  language: string;

  // Custom fields
  tags: string[];
  notes: CustomerNote[];
  customFields: Record<string, any>;

  // Timestamps
  createdAt: Date;
  updatedAt: Date;
}

interface CustomerAddress {
  id: string;
  label: string;           // "Home", "Work", etc.
  recipientName: string;
  phone: string;
  addressLine: string;
  ward?: string;
  district: string;
  province: string;
  postalCode?: string;
  isDefault: boolean;
}

interface CustomerNote {
  id: string;
  content: string;
  createdBy: string;
  createdAt: Date;
}

type CommunicationChannel = 'email' | 'sms' | 'push' | 'zalo';
```

## Database Schema

```prisma
model Customer {
  id              String   @id @default(cuid())
  code            String   @unique
  name            String
  email           String?  @unique
  phone           String   @unique
  dateOfBirth     DateTime?
  gender          Gender?
  avatar          String?

  // CRM
  segment         CustomerSegment @default(NEW)
  loyaltyTier     LoyaltyTier     @default(BRONZE)
  loyaltyPoints   Int             @default(0)
  lifetimeValue   Decimal         @default(0)
  orderCount      Int             @default(0)
  lastOrderAt     DateTime?

  // Preferences
  preferredChannel CommunicationChannel @default(SMS)
  marketingConsent Boolean              @default(false)

  // Relations
  addresses       CustomerAddress[]
  orders          Order[]
  notes           CustomerNote[]
  loyaltyHistory  LoyaltyTransaction[]
  tags            CustomerTag[]

  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  @@index([phone])
  @@index([email])
  @@index([segment])
  @@index([loyaltyTier])
}

enum Gender {
  MALE
  FEMALE
  OTHER
}

enum CustomerSegment {
  CHAMPION
  LOYAL
  POTENTIAL
  NEW
  AT_RISK
  LOST
}

enum LoyaltyTier {
  BRONZE
  SILVER
  GOLD
  PLATINUM
}
```

## API Endpoints

```typescript
// GET /api/crm/customers
// List customers with filters
interface ListCustomersQuery {
  search?: string;          // Name, phone, email
  segment?: CustomerSegment;
  tier?: LoyaltyTier;
  tags?: string[];
  hasEmail?: boolean;
  marketingConsent?: boolean;
  page?: number;
  pageSize?: number;
  sortBy?: 'name' | 'createdAt' | 'lastOrderAt' | 'lifetimeValue';
  sortOrder?: 'asc' | 'desc';
}

// GET /api/crm/customers/:id
// Full customer profile with orders, notes

// PUT /api/crm/customers/:id
// Update customer info

// POST /api/crm/customers/:id/notes
// Add note to customer

// POST /api/crm/customers/:id/tags
// Add tags to customer
```

## Service Implementation

```typescript
// services/customerProfile.ts
export const getCustomerProfile = async (customerId: string): Promise<CustomerProfile> => {
  const customer = await prisma.customer.findUnique({
    where: { id: customerId },
    include: {
      addresses: true,
      notes: {
        orderBy: { createdAt: 'desc' },
        take: 10
      },
      tags: true,
      orders: {
        orderBy: { createdAt: 'desc' },
        take: 5,
        select: {
          id: true,
          orderNumber: true,
          totalAmount: true,
          status: true,
          createdAt: true
        }
      },
      loyaltyHistory: {
        orderBy: { createdAt: 'desc' },
        take: 10
      }
    }
  });

  if (!customer) throw new Error('Customer not found');

  return {
    ...customer,
    customFields: customer.customFields as Record<string, any>
  };
};

export const updateCustomerProfile = async (
  customerId: string,
  data: Partial<CustomerProfile>
): Promise<CustomerProfile> => {
  const updated = await prisma.customer.update({
    where: { id: customerId },
    data: {
      name: data.name,
      email: data.email,
      phone: data.phone,
      dateOfBirth: data.dateOfBirth,
      gender: data.gender,
      preferredChannel: data.preferredChannel,
      marketingConsent: data.marketingConsent
    }
  });

  return getCustomerProfile(updated.id);
};
```

## Components

### CustomerProfileCard

```tsx
interface CustomerProfileCardProps {
  customer: CustomerProfile;
  onEdit?: () => void;
}

const CustomerProfileCard = ({ customer, onEdit }: CustomerProfileCardProps) => (
  <Card>
    <CardHeader className="flex flex-row items-center gap-4">
      <Avatar className="h-16 w-16">
        <AvatarImage src={customer.avatar} />
        <AvatarFallback>{customer.name.charAt(0)}</AvatarFallback>
      </Avatar>
      <div className="flex-1">
        <div className="flex items-center gap-2">
          <h2 className="text-xl font-bold">{customer.name}</h2>
          <SegmentBadge segment={customer.segment} />
          <LoyaltyBadge tier={customer.loyaltyTier} />
        </div>
        <p className="text-sm text-muted-foreground">{customer.code}</p>
      </div>
      {onEdit && (
        <Button variant="outline" size="sm" onClick={onEdit}>
          <Edit className="h-4 w-4 mr-1" /> Edit
        </Button>
      )}
    </CardHeader>

    <CardContent className="space-y-4">
      {/* Contact info */}
      <div className="grid grid-cols-2 gap-4">
        <div className="flex items-center gap-2">
          <Phone className="h-4 w-4 text-muted-foreground" />
          <span>{customer.phone}</span>
        </div>
        {customer.email && (
          <div className="flex items-center gap-2">
            <Mail className="h-4 w-4 text-muted-foreground" />
            <span>{customer.email}</span>
          </div>
        )}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-4 gap-4 pt-4 border-t">
        <StatItem
          label="Lifetime Value"
          value={formatCurrency(customer.lifetimeValue)}
        />
        <StatItem
          label="Orders"
          value={customer.orderCount.toString()}
        />
        <StatItem
          label="Points"
          value={customer.loyaltyPoints.toString()}
        />
        <StatItem
          label="Last Order"
          value={customer.lastOrderAt
            ? formatRelativeDate(customer.lastOrderAt)
            : 'Never'
          }
        />
      </div>

      {/* Tags */}
      {customer.tags.length > 0 && (
        <div className="flex flex-wrap gap-2 pt-4 border-t">
          {customer.tags.map(tag => (
            <Badge key={tag} variant="secondary">{tag}</Badge>
          ))}
        </div>
      )}
    </CardContent>
  </Card>
);
```

### CustomerSearchInput

```tsx
const CustomerSearchInput = ({ onSelect }: { onSelect: (c: Customer) => void }) => {
  const [search, setSearch] = useState('');
  const [results, setResults] = useState<Customer[]>([]);
  const [isOpen, setIsOpen] = useState(false);

  const debouncedSearch = useMemo(
    () => debounce(async (query: string) => {
      if (query.length < 2) return setResults([]);
      const res = await fetch(`/api/crm/customers?search=${query}&pageSize=5`);
      const data = await res.json();
      setResults(data.customers);
    }, 300),
    []
  );

  useEffect(() => {
    debouncedSearch(search);
  }, [search, debouncedSearch]);

  return (
    <Popover open={isOpen && results.length > 0} onOpenChange={setIsOpen}>
      <PopoverTrigger asChild>
        <Input
          placeholder="Search customers..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          onFocus={() => setIsOpen(true)}
        />
      </PopoverTrigger>
      <PopoverContent className="w-[400px] p-0">
        {results.map(customer => (
          <button
            key={customer.id}
            className="w-full p-3 text-left hover:bg-muted flex items-center gap-3"
            onClick={() => {
              onSelect(customer);
              setIsOpen(false);
              setSearch('');
            }}
          >
            <Avatar className="h-8 w-8">
              <AvatarFallback>{customer.name.charAt(0)}</AvatarFallback>
            </Avatar>
            <div>
              <p className="font-medium">{customer.name}</p>
              <p className="text-sm text-muted-foreground">{customer.phone}</p>
            </div>
          </button>
        ))}
      </PopoverContent>
    </Popover>
  );
};
```

## Purchase History

```typescript
interface PurchaseHistoryProps {
  customerId: string;
}

const PurchaseHistory = ({ customerId }: PurchaseHistoryProps) => {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-orders', customerId],
    queryFn: () => fetch(`/api/crm/customers/${customerId}/orders`).then(r => r.json())
  });

  if (isLoading) return <Skeleton className="h-48" />;

  return (
    <div className="space-y-4">
      <h3 className="font-semibold">Purchase History</h3>
      {data.orders.map((order: Order) => (
        <div key={order.id} className="flex items-center justify-between p-3 border rounded">
          <div>
            <p className="font-medium">{order.orderNumber}</p>
            <p className="text-sm text-muted-foreground">
              {formatDate(order.createdAt)}
            </p>
          </div>
          <div className="text-right">
            <p className="font-medium">{formatCurrency(order.totalAmount)}</p>
            <OrderStatusBadge status={order.status} />
          </div>
        </div>
      ))}
    </div>
  );
};
```
