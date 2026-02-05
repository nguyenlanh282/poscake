# Passkeys / WebAuthn

## Overview

Passkeys cho phép đăng nhập bằng biometric (fingerprint, Face ID) hoặc device PIN, không cần password.

## Setup

```typescript
// lib/auth.ts
import { betterAuth } from 'better-auth';
import { passkey } from 'better-auth/plugins';

export const auth = betterAuth({
  plugins: [
    passkey({
      rpID: 'localhost',  // Your domain
      rpName: 'MyPOS App',
      origin: process.env.BETTER_AUTH_URL
    })
  ]
});
```

## Client Setup

```typescript
// lib/auth-client.ts
import { createAuthClient } from 'better-auth/react';
import { passkeyClient } from 'better-auth/client/plugins';

export const authClient = createAuthClient({
  plugins: [passkeyClient()]
});
```

## Register Passkey

```tsx
'use client';
import { authClient } from '@/lib/auth-client';

export function RegisterPasskey() {
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);

  const handleRegister = async () => {
    setLoading(true);

    const { error } = await authClient.passkey.addPasskey({
      name: 'My Device'  // Optional name for the passkey
    });

    if (!error) {
      setSuccess(true);
    }

    setLoading(false);
  };

  if (success) {
    return (
      <div className="text-center">
        <CheckCircle className="mx-auto h-12 w-12 text-green-500" />
        <p>Passkey registered successfully!</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h2>Add Passkey</h2>
      <p className="text-muted-foreground">
        Use your fingerprint, face, or device PIN to sign in
      </p>
      <Button onClick={handleRegister} disabled={loading}>
        {loading ? (
          <>
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Registering...
          </>
        ) : (
          <>
            <Fingerprint className="mr-2 h-4 w-4" />
            Register Passkey
          </>
        )}
      </Button>
    </div>
  );
}
```

## Login with Passkey

```tsx
export function PasskeyLogin() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handlePasskeyLogin = async () => {
    setLoading(true);
    setError('');

    const { error } = await authClient.signIn.passkey();

    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }

    router.push('/dashboard');
  };

  return (
    <div className="space-y-4">
      <Button
        variant="outline"
        onClick={handlePasskeyLogin}
        disabled={loading}
        className="w-full"
      >
        {loading ? (
          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
        ) : (
          <Fingerprint className="mr-2 h-4 w-4" />
        )}
        Sign in with Passkey
      </Button>
      {error && <p className="text-red-500 text-sm">{error}</p>}
    </div>
  );
}
```

## List & Manage Passkeys

```tsx
export function ManagePasskeys() {
  const [passkeys, setPasskeys] = useState<Passkey[]>([]);

  useEffect(() => {
    authClient.passkey.listPasskeys().then(({ data }) => {
      setPasskeys(data || []);
    });
  }, []);

  const deletePasskey = async (id: string) => {
    await authClient.passkey.deletePasskey({ id });
    setPasskeys(passkeys.filter(p => p.id !== id));
  };

  return (
    <div>
      <h2>Your Passkeys</h2>
      {passkeys.length === 0 ? (
        <p>No passkeys registered</p>
      ) : (
        <ul className="space-y-2">
          {passkeys.map((passkey) => (
            <li key={passkey.id} className="flex items-center justify-between p-3 border rounded">
              <div>
                <p className="font-medium">{passkey.name || 'Unnamed Passkey'}</p>
                <p className="text-sm text-muted-foreground">
                  Created: {formatDate(passkey.createdAt)}
                </p>
              </div>
              <Button
                variant="destructive"
                size="sm"
                onClick={() => deletePasskey(passkey.id)}
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </li>
          ))}
        </ul>
      )}
      <RegisterPasskey />
    </div>
  );
}
```

## Check Passkey Support

```typescript
// Check if browser supports WebAuthn
const isPasskeySupported = () => {
  return window.PublicKeyCredential !== undefined &&
    typeof window.PublicKeyCredential === 'function';
};

// Check if platform authenticator available (Touch ID, Face ID)
const isPlatformAuthenticatorAvailable = async () => {
  if (!isPasskeySupported()) return false;
  return await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
};
```

## Conditional UI

```tsx
function AuthOptions() {
  const [passkeyAvailable, setPasskeyAvailable] = useState(false);

  useEffect(() => {
    isPlatformAuthenticatorAvailable().then(setPasskeyAvailable);
  }, []);

  return (
    <div className="space-y-4">
      {passkeyAvailable && <PasskeyLogin />}

      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-background px-2 text-muted-foreground">
            Or continue with
          </span>
        </div>
      </div>

      <LoginForm />
      <OAuthButtons />
    </div>
  );
}
```

## Production Configuration

```typescript
// lib/auth.ts
passkey({
  rpID: process.env.NODE_ENV === 'production'
    ? 'mypos.com'
    : 'localhost',
  rpName: 'MyPOS App',
  origin: process.env.BETTER_AUTH_URL,
  authenticatorSelection: {
    authenticatorAttachment: 'platform',  // Built-in (Touch ID, Face ID)
    userVerification: 'required',
    residentKey: 'required'
  }
})
```
