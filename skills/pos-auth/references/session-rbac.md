# Session Management & RBAC

## Session Configuration

```typescript
// lib/auth.ts
import { betterAuth } from 'better-auth';

export const auth = betterAuth({
  session: {
    expiresIn: 60 * 60 * 24 * 7,  // 7 days
    updateAge: 60 * 60 * 24,      // Update session every 24 hours
    cookieCache: {
      enabled: true,
      maxAge: 60 * 5  // 5 minutes cache
    }
  }
});
```

## Get Current Session

```tsx
'use client';
import { useSession } from '@/lib/auth-client';

export function UserProfile() {
  const { data: session, isPending } = useSession();

  if (isPending) return <Skeleton />;
  if (!session) return <LoginButton />;

  return (
    <div>
      <p>Welcome, {session.user.name}</p>
      <p>Email: {session.user.email}</p>
      <p>Role: {session.user.role}</p>
    </div>
  );
}
```

## Server-side Session

```typescript
// app/dashboard/page.tsx
import { auth } from '@/lib/auth';
import { headers } from 'next/headers';
import { redirect } from 'next/navigation';

export default async function DashboardPage() {
  const session = await auth.api.getSession({
    headers: await headers()
  });

  if (!session) {
    redirect('/login');
  }

  return <Dashboard user={session.user} />;
}
```

## Middleware Protection

```typescript
// middleware.ts
import { auth } from '@/lib/auth';
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export async function middleware(request: NextRequest) {
  const session = await auth.api.getSession({
    headers: request.headers
  });

  // Protected routes
  if (request.nextUrl.pathname.startsWith('/dashboard')) {
    if (!session) {
      return NextResponse.redirect(new URL('/login', request.url));
    }
  }

  // Admin only routes
  if (request.nextUrl.pathname.startsWith('/admin')) {
    if (!session || session.user.role !== 'ADMIN') {
      return NextResponse.redirect(new URL('/unauthorized', request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*', '/admin/:path*']
};
```

## Role-Based Access Control (RBAC)

### Setup Admin Plugin

```typescript
// lib/auth.ts
import { admin } from 'better-auth/plugins';

export const auth = betterAuth({
  plugins: [
    admin({
      defaultRole: 'STAFF',
      adminRole: 'ADMIN'
    })
  ]
});
```

### Define Roles

```typescript
// types/auth.ts
export const ROLES = {
  ADMIN: 'ADMIN',
  MANAGER: 'MANAGER',
  STAFF: 'STAFF',
  CASHIER: 'CASHIER'
} as const;

export type Role = keyof typeof ROLES;

export const PERMISSIONS = {
  // Products
  'products:read': ['ADMIN', 'MANAGER', 'STAFF', 'CASHIER'],
  'products:create': ['ADMIN', 'MANAGER'],
  'products:update': ['ADMIN', 'MANAGER'],
  'products:delete': ['ADMIN'],

  // Orders
  'orders:read': ['ADMIN', 'MANAGER', 'STAFF', 'CASHIER'],
  'orders:create': ['ADMIN', 'MANAGER', 'STAFF', 'CASHIER'],
  'orders:update': ['ADMIN', 'MANAGER', 'STAFF'],
  'orders:delete': ['ADMIN'],
  'orders:refund': ['ADMIN', 'MANAGER'],

  // Reports
  'reports:read': ['ADMIN', 'MANAGER'],
  'reports:export': ['ADMIN', 'MANAGER'],

  // Settings
  'settings:read': ['ADMIN', 'MANAGER'],
  'settings:update': ['ADMIN']
} as const;
```

### Check Permissions

```typescript
// lib/permissions.ts
export function hasPermission(
  userRole: Role,
  permission: keyof typeof PERMISSIONS
): boolean {
  return PERMISSIONS[permission].includes(userRole);
}

// Usage in component
function DeleteProductButton({ productId }: { productId: string }) {
  const { data: session } = useSession();

  if (!hasPermission(session?.user.role, 'products:delete')) {
    return null;
  }

  return (
    <Button variant="destructive" onClick={() => deleteProduct(productId)}>
      Delete
    </Button>
  );
}
```

### Server-side Authorization

```typescript
// app/api/products/[id]/route.ts
import { auth } from '@/lib/auth';
import { hasPermission } from '@/lib/permissions';

export async function DELETE(
  req: Request,
  { params }: { params: { id: string } }
) {
  const session = await auth.api.getSession({ headers: req.headers });

  if (!session) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  if (!hasPermission(session.user.role, 'products:delete')) {
    return Response.json({ error: 'Forbidden' }, { status: 403 });
  }

  await deleteProduct(params.id);
  return Response.json({ success: true });
}
```

## Session Management UI

```tsx
export function ActiveSessions() {
  const [sessions, setSessions] = useState<Session[]>([]);

  useEffect(() => {
    authClient.listSessions().then(({ data }) => setSessions(data || []));
  }, []);

  const revokeSession = async (token: string) => {
    await authClient.revokeSession({ token });
    setSessions(sessions.filter(s => s.token !== token));
  };

  const revokeAllOtherSessions = async () => {
    await authClient.revokeOtherSessions();
    // Keep only current session
  };

  return (
    <div>
      <h2>Active Sessions</h2>
      <Button variant="outline" onClick={revokeAllOtherSessions}>
        Sign out all other devices
      </Button>
      <ul className="space-y-2 mt-4">
        {sessions.map((session) => (
          <li key={session.token} className="flex items-center justify-between p-3 border rounded">
            <div>
              <p className="font-medium">{session.userAgent}</p>
              <p className="text-sm text-muted-foreground">
                {session.ipAddress} • Last active: {formatDate(session.lastActiveAt)}
              </p>
            </div>
            {!session.isCurrent && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => revokeSession(session.token)}
              >
                Revoke
              </Button>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
```

## Rate Limiting

```typescript
// lib/auth.ts
import { rateLimit } from 'better-auth/plugins';

export const auth = betterAuth({
  plugins: [
    rateLimit({
      window: 60,       // 60 seconds
      max: 10,          // Max 10 requests
      customRules: {
        '/sign-in/email': { window: 60, max: 5 },
        '/sign-up/email': { window: 3600, max: 3 }  // 3 signups per hour
      }
    })
  ]
});
```
