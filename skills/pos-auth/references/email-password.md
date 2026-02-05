# Email/Password Authentication

## Setup

```typescript
// lib/auth.ts
import { betterAuth } from 'better-auth';

export const auth = betterAuth({
  emailAndPassword: {
    enabled: true,
    requireEmailVerification: true,
    sendResetPassword: async ({ user, url }) => {
      await sendEmail({
        to: user.email,
        subject: 'Reset your password',
        html: `<a href="${url}">Click here to reset password</a>`
      });
    }
  }
});
```

## API Routes (Next.js App Router)

```typescript
// app/api/auth/[...all]/route.ts
import { auth } from '@/lib/auth';
import { toNextJsHandler } from 'better-auth/next-js';

export const { GET, POST } = toNextJsHandler(auth);
```

## Client Setup

```typescript
// lib/auth-client.ts
import { createAuthClient } from 'better-auth/react';

export const authClient = createAuthClient({
  baseURL: process.env.NEXT_PUBLIC_APP_URL
});

export const { signIn, signUp, signOut, useSession } = authClient;
```

## Registration Form

```tsx
'use client';
import { useState } from 'react';
import { signUp } from '@/lib/auth-client';
import { useRouter } from 'next/navigation';

export function RegisterForm() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    const formData = new FormData(e.currentTarget);
    const { error } = await signUp.email({
      email: formData.get('email') as string,
      password: formData.get('password') as string,
      name: formData.get('name') as string
    });

    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }

    router.push('/verify-email');
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <Label htmlFor="name">Name</Label>
        <Input id="name" name="name" required />
      </div>
      <div>
        <Label htmlFor="email">Email</Label>
        <Input id="email" name="email" type="email" required />
      </div>
      <div>
        <Label htmlFor="password">Password</Label>
        <Input id="password" name="password" type="password" minLength={8} required />
      </div>
      {error && <p className="text-red-500 text-sm">{error}</p>}
      <Button type="submit" disabled={loading} className="w-full">
        {loading ? 'Creating account...' : 'Create account'}
      </Button>
    </form>
  );
}
```

## Login Form

```tsx
'use client';
import { signIn } from '@/lib/auth-client';

export function LoginForm() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setLoading(true);

    const formData = new FormData(e.currentTarget);
    const { error } = await signIn.email({
      email: formData.get('email') as string,
      password: formData.get('password') as string
    });

    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }

    router.push('/dashboard');
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <Label htmlFor="email">Email</Label>
        <Input id="email" name="email" type="email" required />
      </div>
      <div>
        <Label htmlFor="password">Password</Label>
        <Input id="password" name="password" type="password" required />
      </div>
      {error && <p className="text-red-500 text-sm">{error}</p>}
      <Button type="submit" disabled={loading} className="w-full">
        {loading ? 'Signing in...' : 'Sign in'}
      </Button>
      <Link href="/forgot-password" className="text-sm text-muted-foreground">
        Forgot password?
      </Link>
    </form>
  );
}
```

## Password Reset

```tsx
// Request reset
export function ForgotPasswordForm() {
  const [sent, setSent] = useState(false);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);

    await authClient.forgetPassword({
      email: formData.get('email') as string,
      redirectTo: '/reset-password'
    });

    setSent(true);
  };

  if (sent) {
    return <p>Check your email for reset link</p>;
  }

  return (
    <form onSubmit={handleSubmit}>
      <Input name="email" type="email" placeholder="Enter your email" required />
      <Button type="submit">Send reset link</Button>
    </form>
  );
}

// Reset password page
export function ResetPasswordForm({ token }: { token: string }) {
  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);

    await authClient.resetPassword({
      newPassword: formData.get('password') as string,
      token
    });
  };

  return (
    <form onSubmit={handleSubmit}>
      <Input name="password" type="password" placeholder="New password" minLength={8} required />
      <Button type="submit">Reset password</Button>
    </form>
  );
}
```

## Email Verification

```typescript
// Send verification email on signup
emailAndPassword: {
  requireEmailVerification: true,
  sendVerificationEmail: async ({ user, url }) => {
    await sendEmail({
      to: user.email,
      subject: 'Verify your email',
      html: `<a href="${url}">Click to verify</a>`
    });
  }
}
```
