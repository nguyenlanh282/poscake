---
name: pos-auth
description: |
  Implement authentication for POS systems using Better Auth framework. Features:
  email/password with verification, OAuth providers (Google, GitHub, Facebook, Discord),
  two-factor authentication (TOTP, SMS OTP), passkeys/WebAuthn biometric login,
  session management, role-based access control (RBAC), rate limiting.
  Use when building login/register flows, implementing OAuth, adding 2FA/MFA,
  or securing POS applications with modern authentication.
version: 1.0.0
---

# POS Authentication

Implement authentication cho hệ thống POS với Better Auth.

## Why Better Auth?

- Framework-agnostic (Next.js, Remix, SvelteKit, Express...)
- TypeScript-first với full type safety
- Built-in plugins: 2FA, passkeys, RBAC, rate limiting
- Database adapters: Prisma, Drizzle, MongoDB...

## Auth Methods

### 1. Email/Password
Reference: [references/email-password.md](references/email-password.md)
- Register, login, email verification, password reset

### 2. OAuth Providers
Reference: [references/oauth.md](references/oauth.md)
- Google, GitHub, Facebook, Discord integration

### 3. Two-Factor Authentication
Reference: [references/2fa.md](references/2fa.md)
- TOTP (Google Authenticator), SMS OTP, backup codes

### 4. Passkeys/Biometric
Reference: [references/passkeys.md](references/passkeys.md)
- WebAuthn, fingerprint, Face ID

### 5. Session & RBAC
Reference: [references/session-rbac.md](references/session-rbac.md)
- Session management, roles, permissions

## Quick Start

```bash
npm install better-auth
```

```typescript
// lib/auth.ts
import { betterAuth } from 'better-auth';
import { prismaAdapter } from 'better-auth/adapters/prisma';
import { twoFactor, passkey, admin } from 'better-auth/plugins';

export const auth = betterAuth({
  database: prismaAdapter(prisma, { provider: 'postgresql' }),
  emailAndPassword: { enabled: true },
  socialProviders: {
    google: {
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!
    }
  },
  plugins: [
    twoFactor(),
    passkey(),
    admin()
  ]
});
```

## Environment Variables

```env
# Better Auth
BETTER_AUTH_SECRET=your-secret-key
BETTER_AUTH_URL=http://localhost:3000

# OAuth - Google
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

# OAuth - GitHub
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=

# OAuth - Facebook
FACEBOOK_CLIENT_ID=
FACEBOOK_CLIENT_SECRET=

# SMS (Twilio)
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=

# Email (Resend/SendGrid)
RESEND_API_KEY=
EMAIL_FROM=noreply@yourapp.com
```

## Database Schema

Better Auth tự động tạo tables: `user`, `session`, `account`, `verification`.

Thêm fields cho POS:

```prisma
model User {
  // Better Auth fields (auto-generated)
  id            String   @id
  email         String   @unique
  emailVerified Boolean  @default(false)
  // ...

  // POS custom fields
  role          Role     @default(STAFF)
  shopId        String?
  isActive      Boolean  @default(true)
}

enum Role {
  ADMIN
  MANAGER
  STAFF
  CASHIER
}
```

## Components

```
components/auth/
├── LoginForm.tsx         # Email/password login
├── RegisterForm.tsx      # Registration
├── OAuthButtons.tsx      # Social login buttons
├── TwoFactorSetup.tsx    # Enable 2FA
├── TwoFactorVerify.tsx   # Verify 2FA code
├── PasskeyRegister.tsx   # Register passkey
├── PasskeyLogin.tsx      # Login with passkey
├── ForgotPassword.tsx    # Password reset request
├── ResetPassword.tsx     # Set new password
└── UserMenu.tsx          # Logged in user dropdown
```
