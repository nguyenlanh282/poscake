# Card Payment Integration

## Stripe

### Setup

```bash
npm install stripe @stripe/stripe-js @stripe/react-stripe-js
```

### Server-side

```typescript
import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

// Create Payment Intent
async function createPaymentIntent(orderId: string, amount: number) {
  const paymentIntent = await stripe.paymentIntents.create({
    amount: amount,  // In smallest currency unit (cents/đồng)
    currency: 'vnd',
    metadata: { orderId },
    automatic_payment_methods: { enabled: true }
  });

  return {
    clientSecret: paymentIntent.client_secret,
    paymentIntentId: paymentIntent.id
  };
}

// Webhook handler
// POST /api/webhooks/stripe
export async function POST(req: Request) {
  const body = await req.text();
  const signature = req.headers.get('stripe-signature')!;

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(
      body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch (err) {
    return Response.json({ error: 'Invalid signature' }, { status: 400 });
  }

  switch (event.type) {
    case 'payment_intent.succeeded':
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      await updateOrderPayment(paymentIntent.metadata.orderId, {
        status: 'paid',
        transactionId: paymentIntent.id
      });
      break;
    case 'payment_intent.payment_failed':
      // Handle failed payment
      break;
  }

  return Response.json({ received: true });
}
```

### Client-side Component

```tsx
import { loadStripe } from '@stripe/stripe-js';
import { Elements, PaymentElement, useStripe, useElements } from '@stripe/react-stripe-js';

const stripePromise = loadStripe(process.env.NEXT_PUBLIC_STRIPE_KEY!);

function CheckoutForm({ onSuccess }: { onSuccess: () => void }) {
  const stripe = useStripe();
  const elements = useElements();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!stripe || !elements) return;

    setLoading(true);
    const { error } = await stripe.confirmPayment({
      elements,
      confirmParams: {
        return_url: `${window.location.origin}/payment/success`
      }
    });

    if (error) {
      setError(error.message);
    }
    setLoading(false);
  };

  return (
    <form onSubmit={handleSubmit}>
      <PaymentElement />
      {error && <p className="text-red-500">{error}</p>}
      <Button type="submit" disabled={!stripe || loading}>
        {loading ? 'Processing...' : 'Pay Now'}
      </Button>
    </form>
  );
}

function CardPayment({ clientSecret }: { clientSecret: string }) {
  return (
    <Elements stripe={stripePromise} options={{ clientSecret }}>
      <CheckoutForm onSuccess={() => {}} />
    </Elements>
  );
}
```

---

## PayOS (Vietnamese Card Gateway)

PayOS hỗ trợ thẻ nội địa (Napas) và quốc tế.

### Setup

```bash
npm install @payos/node
```

### Create Payment Link

```typescript
import PayOS from '@payos/node';

const payos = new PayOS(
  process.env.PAYOS_CLIENT_ID!,
  process.env.PAYOS_API_KEY!,
  process.env.PAYOS_CHECKSUM_KEY!
);

async function createPayOSPayment(orderId: string, amount: number, items: any[]) {
  const orderCode = Number(orderId.replace(/\D/g, '').slice(-8));

  const paymentLink = await payos.createPaymentLink({
    orderCode,
    amount,
    description: `Order #${orderId}`,
    items: items.map(item => ({
      name: item.name,
      quantity: item.quantity,
      price: item.price
    })),
    cancelUrl: `${process.env.APP_URL}/payment/cancel`,
    returnUrl: `${process.env.APP_URL}/payment/success`
  });

  return paymentLink.checkoutUrl;
}
```

### Verify Payment

```typescript
async function verifyPayOSPayment(orderCode: number) {
  const payment = await payos.getPaymentLinkInformation(orderCode);
  return {
    status: payment.status,  // PAID, PENDING, CANCELLED
    amount: payment.amount,
    paidAt: payment.transactions?.[0]?.transactionDateTime
  };
}
```

### Webhook

```typescript
// POST /api/webhooks/payos
export async function POST(req: Request) {
  const body = await req.json();

  const isValid = payos.verifyPaymentWebhookData(body);
  if (!isValid) {
    return Response.json({ error: 'Invalid signature' }, { status: 401 });
  }

  const { orderCode, code } = body.data;

  if (code === '00') {  // Success
    await updateOrderPayment(orderCode.toString(), { status: 'paid' });
  }

  return Response.json({ success: true });
}
```

---

## Environment Variables

```env
# Stripe
STRIPE_SECRET_KEY=sk_test_...
NEXT_PUBLIC_STRIPE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# PayOS
PAYOS_CLIENT_ID=
PAYOS_API_KEY=
PAYOS_CHECKSUM_KEY=
```

## Security Checklist

- [ ] Always verify webhook signatures
- [ ] Use HTTPS for all payment endpoints
- [ ] Never log full card numbers
- [ ] Implement idempotency for payment processing
- [ ] Store sensitive keys in environment variables
- [ ] Use test/sandbox mode during development
