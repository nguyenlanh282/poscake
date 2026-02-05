# Two-Factor Authentication (2FA)

## Setup

```typescript
// lib/auth.ts
import { betterAuth } from 'better-auth';
import { twoFactor } from 'better-auth/plugins';

export const auth = betterAuth({
  plugins: [
    twoFactor({
      issuer: 'MyPOS App',  // Shown in authenticator app
      otpOptions: {
        digits: 6,
        period: 30  // seconds
      }
    })
  ]
});
```

## Client Setup

```typescript
// lib/auth-client.ts
import { createAuthClient } from 'better-auth/react';
import { twoFactorClient } from 'better-auth/client/plugins';

export const authClient = createAuthClient({
  plugins: [twoFactorClient()]
});
```

## Enable 2FA Flow

### Step 1: Generate TOTP Secret

```tsx
'use client';
import { useState } from 'react';
import { authClient } from '@/lib/auth-client';
import QRCode from 'qrcode.react';

export function TwoFactorSetup() {
  const [totpURI, setTotpURI] = useState<string>();
  const [backupCodes, setBackupCodes] = useState<string[]>();
  const [step, setStep] = useState<'init' | 'verify' | 'done'>('init');

  const enableTwoFactor = async () => {
    const { data } = await authClient.twoFactor.enable();
    setTotpURI(data.totpURI);
    setBackupCodes(data.backupCodes);
    setStep('verify');
  };

  const verifyAndActivate = async (code: string) => {
    const { error } = await authClient.twoFactor.verifyTotp({ code });
    if (!error) {
      setStep('done');
    }
  };

  if (step === 'init') {
    return (
      <div>
        <h2>Enable Two-Factor Authentication</h2>
        <p>Add an extra layer of security to your account</p>
        <Button onClick={enableTwoFactor}>Enable 2FA</Button>
      </div>
    );
  }

  if (step === 'verify') {
    return (
      <div className="space-y-4">
        <h2>Scan QR Code</h2>
        <p>Use Google Authenticator or similar app</p>

        {totpURI && <QRCode value={totpURI} size={200} />}

        <div>
          <h3>Backup Codes</h3>
          <p className="text-sm text-muted-foreground">
            Save these codes in a safe place
          </p>
          <div className="grid grid-cols-2 gap-2 font-mono text-sm">
            {backupCodes?.map((code, i) => (
              <div key={i} className="bg-muted p-2 rounded">{code}</div>
            ))}
          </div>
        </div>

        <VerifyCodeForm onVerify={verifyAndActivate} />
      </div>
    );
  }

  return (
    <div className="text-center">
      <CheckCircle className="mx-auto h-12 w-12 text-green-500" />
      <h2>2FA Enabled!</h2>
      <p>Your account is now protected with two-factor authentication</p>
    </div>
  );
}
```

### Step 2: Verify Code Component

```tsx
function VerifyCodeForm({ onVerify }: { onVerify: (code: string) => void }) {
  const [code, setCode] = useState('');

  return (
    <div className="space-y-4">
      <Label>Enter 6-digit code</Label>
      <InputOTP
        maxLength={6}
        value={code}
        onChange={setCode}
        onComplete={onVerify}
      >
        <InputOTPGroup>
          <InputOTPSlot index={0} />
          <InputOTPSlot index={1} />
          <InputOTPSlot index={2} />
          <InputOTPSlot index={3} />
          <InputOTPSlot index={4} />
          <InputOTPSlot index={5} />
        </InputOTPGroup>
      </InputOTP>
      <Button onClick={() => onVerify(code)} disabled={code.length !== 6}>
        Verify
      </Button>
    </div>
  );
}
```

## Login with 2FA

```tsx
export function LoginWith2FA() {
  const [requires2FA, setRequires2FA] = useState(false);

  const handleLogin = async (email: string, password: string) => {
    const { error, data } = await signIn.email({ email, password });

    if (data?.twoFactorRedirect) {
      setRequires2FA(true);
      return;
    }

    if (!error) {
      router.push('/dashboard');
    }
  };

  const handleVerify2FA = async (code: string) => {
    const { error } = await authClient.twoFactor.verifyTotp({ code });
    if (!error) {
      router.push('/dashboard');
    }
  };

  if (requires2FA) {
    return <VerifyCodeForm onVerify={handleVerify2FA} />;
  }

  return <LoginForm onSubmit={handleLogin} />;
}
```

## Disable 2FA

```typescript
await authClient.twoFactor.disable({
  password: 'current-password'  // Require password confirmation
});
```

## SMS OTP (Twilio)

```typescript
// lib/auth.ts
twoFactor({
  smsOTP: {
    sendOTP: async ({ user, otp }) => {
      await twilioClient.messages.create({
        to: user.phoneNumber,
        from: process.env.TWILIO_PHONE_NUMBER,
        body: `Your verification code is: ${otp}`
      });
    }
  }
})

// Client - request SMS OTP
await authClient.twoFactor.sendSmsOtp();

// Verify SMS OTP
await authClient.twoFactor.verifySmsOtp({ code: '123456' });
```

## Backup Codes

```typescript
// Use backup code when authenticator not available
await authClient.twoFactor.verifyBackupCode({
  code: 'xxxx-xxxx-xxxx'
});

// Regenerate backup codes
const { data } = await authClient.twoFactor.regenerateBackupCodes();
// data.backupCodes = ['xxxx-xxxx', ...]
```
