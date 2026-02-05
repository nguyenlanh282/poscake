# OAuth Providers

## Setup

```typescript
// lib/auth.ts
import { betterAuth } from 'better-auth';

export const auth = betterAuth({
  socialProviders: {
    google: {
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!
    },
    github: {
      clientId: process.env.GITHUB_CLIENT_ID!,
      clientSecret: process.env.GITHUB_CLIENT_SECRET!
    },
    facebook: {
      clientId: process.env.FACEBOOK_CLIENT_ID!,
      clientSecret: process.env.FACEBOOK_CLIENT_SECRET!
    },
    discord: {
      clientId: process.env.DISCORD_CLIENT_ID!,
      clientSecret: process.env.DISCORD_CLIENT_SECRET!
    }
  }
});
```

## OAuth Buttons Component

```tsx
'use client';
import { signIn } from '@/lib/auth-client';
import { Button } from '@/components/ui/button';
import { Icons } from '@/components/icons';

export function OAuthButtons() {
  const handleOAuth = async (provider: 'google' | 'github' | 'facebook' | 'discord') => {
    await signIn.social({
      provider,
      callbackURL: '/dashboard'
    });
  };

  return (
    <div className="grid grid-cols-2 gap-4">
      <Button variant="outline" onClick={() => handleOAuth('google')}>
        <Icons.google className="mr-2 h-4 w-4" />
        Google
      </Button>
      <Button variant="outline" onClick={() => handleOAuth('github')}>
        <Icons.github className="mr-2 h-4 w-4" />
        GitHub
      </Button>
      <Button variant="outline" onClick={() => handleOAuth('facebook')}>
        <Icons.facebook className="mr-2 h-4 w-4" />
        Facebook
      </Button>
      <Button variant="outline" onClick={() => handleOAuth('discord')}>
        <Icons.discord className="mr-2 h-4 w-4" />
        Discord
      </Button>
    </div>
  );
}
```

## Provider Setup Guides

### Google

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create project > APIs & Services > Credentials
3. Create OAuth 2.0 Client ID
4. Add authorized redirect URI: `http://localhost:3000/api/auth/callback/google`

```env
GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-xxx
```

### GitHub

1. Go to [GitHub Developer Settings](https://github.com/settings/developers)
2. New OAuth App
3. Authorization callback URL: `http://localhost:3000/api/auth/callback/github`

```env
GITHUB_CLIENT_ID=Ov23li...
GITHUB_CLIENT_SECRET=xxx
```

### Facebook

1. Go to [Facebook Developers](https://developers.facebook.com)
2. Create App > Consumer
3. Add Facebook Login product
4. Valid OAuth Redirect URIs: `http://localhost:3000/api/auth/callback/facebook`

```env
FACEBOOK_CLIENT_ID=123456789
FACEBOOK_CLIENT_SECRET=xxx
```

### Discord

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. New Application > OAuth2
3. Add redirect: `http://localhost:3000/api/auth/callback/discord`

```env
DISCORD_CLIENT_ID=123456789
DISCORD_CLIENT_SECRET=xxx
```

## Account Linking

Cho phép user link nhiều providers:

```typescript
// Link thêm provider vào account hiện có
await authClient.linkSocial({
  provider: 'github',
  callbackURL: '/settings/accounts'
});

// Unlink provider
await authClient.unlinkAccount({
  providerId: 'github'
});
```

## Get User Accounts

```typescript
// Lấy danh sách linked accounts
const accounts = await authClient.listAccounts();
// [{ provider: 'google', ... }, { provider: 'github', ... }]
```

## Custom OAuth Scopes

```typescript
socialProviders: {
  google: {
    clientId: process.env.GOOGLE_CLIENT_ID!,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    scope: ['email', 'profile', 'openid']
  }
}
```

## Handle OAuth Errors

```tsx
// app/auth/error/page.tsx
export default function AuthErrorPage({
  searchParams
}: {
  searchParams: { error?: string }
}) {
  const errorMessages: Record<string, string> = {
    OAuthAccountNotLinked: 'Email already exists with different provider',
    OAuthCallbackError: 'OAuth callback failed',
    AccessDenied: 'Access denied by provider'
  };

  return (
    <div className="text-center">
      <h1>Authentication Error</h1>
      <p>{errorMessages[searchParams.error || ''] || 'Unknown error'}</p>
      <Link href="/login">Try again</Link>
    </div>
  );
}
```
