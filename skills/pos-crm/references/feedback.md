# Feedback & Support

Thu thập feedback và quản lý support tickets.

## Overview

Feedback collection giúp hiểu customer satisfaction và support tickets giúp giải quyết vấn đề nhanh chóng.

## Data Models

```typescript
// Survey
interface Survey {
  id: string;
  name: string;
  type: SurveyType;
  questions: SurveyQuestion[];
  trigger?: SurveyTrigger;
  status: 'draft' | 'active' | 'paused' | 'completed';
  responseCount: number;
  avgRating?: number;
  createdAt: Date;
}

type SurveyType = 'nps' | 'csat' | 'ces' | 'custom';

interface SurveyQuestion {
  id: string;
  type: 'rating' | 'nps' | 'text' | 'choice' | 'multiple_choice';
  question: string;
  required: boolean;
  options?: string[];        // For choice/multiple_choice
  scale?: number;            // For rating (1-5, 1-10)
}

interface SurveyTrigger {
  event: 'order_completed' | 'support_closed' | 'days_since_purchase';
  delay?: string;            // e.g., "1d"
  conditions?: TriggerCondition[];
}

interface SurveyResponse {
  id: string;
  surveyId: string;
  customerId: string;
  orderId?: string;
  answers: SurveyAnswer[];
  submittedAt: Date;
}

interface SurveyAnswer {
  questionId: string;
  value: number | string | string[];
}

// Reviews
interface ProductReview {
  id: string;
  productId: string;
  customerId: string;
  orderId: string;
  rating: number;            // 1-5
  title?: string;
  content: string;
  images?: string[];
  isVerified: boolean;       // Verified purchase
  status: ReviewStatus;
  helpfulCount: number;
  createdAt: Date;
}

type ReviewStatus = 'pending' | 'approved' | 'rejected';

// Support Tickets
interface SupportTicket {
  id: string;
  ticketNumber: string;      // TKT-2024-0001
  customerId: string;
  orderId?: string;

  category: TicketCategory;
  priority: TicketPriority;
  status: TicketStatus;

  subject: string;
  description: string;
  attachments?: string[];

  assignedTo?: string;
  messages: TicketMessage[];

  createdAt: Date;
  updatedAt: Date;
  resolvedAt?: Date;
}

type TicketCategory = 'order' | 'product' | 'payment' | 'delivery' | 'return' | 'other';
type TicketPriority = 'low' | 'medium' | 'high' | 'urgent';
type TicketStatus = 'open' | 'in_progress' | 'waiting_customer' | 'resolved' | 'closed';

interface TicketMessage {
  id: string;
  sender: 'customer' | 'agent';
  senderId: string;
  content: string;
  attachments?: string[];
  createdAt: Date;
}
```

## NPS (Net Promoter Score)

```typescript
// NPS calculation
interface NPSResult {
  score: number;              // -100 to 100
  promoters: number;          // 9-10
  passives: number;           // 7-8
  detractors: number;         // 0-6
  totalResponses: number;
}

export const calculateNPS = async (surveyId: string): Promise<NPSResult> => {
  const responses = await prisma.surveyResponse.findMany({
    where: { surveyId },
    include: { answers: true }
  });

  const npsAnswers = responses
    .map(r => r.answers.find(a => a.questionId === 'nps'))
    .filter(Boolean)
    .map(a => a.value as number);

  const promoters = npsAnswers.filter(v => v >= 9).length;
  const passives = npsAnswers.filter(v => v >= 7 && v <= 8).length;
  const detractors = npsAnswers.filter(v => v <= 6).length;

  const total = npsAnswers.length;
  const score = ((promoters - detractors) / total) * 100;

  return {
    score: Math.round(score),
    promoters,
    passives,
    detractors,
    totalResponses: total
  };
};
```

## Post-Purchase Survey

```typescript
const postPurchaseSurvey: Survey = {
  id: 'post-purchase',
  name: 'Post-Purchase Feedback',
  type: 'csat',
  trigger: {
    event: 'order_completed',
    delay: '1d'
  },
  questions: [
    {
      id: 'overall',
      type: 'rating',
      question: 'How satisfied are you with your purchase?',
      required: true,
      scale: 5
    },
    {
      id: 'product_quality',
      type: 'rating',
      question: 'How would you rate the product quality?',
      required: true,
      scale: 5
    },
    {
      id: 'delivery',
      type: 'rating',
      question: 'How was the delivery experience?',
      required: true,
      scale: 5
    },
    {
      id: 'nps',
      type: 'nps',
      question: 'How likely are you to recommend us to a friend?',
      required: true
    },
    {
      id: 'feedback',
      type: 'text',
      question: 'Any additional feedback?',
      required: false
    }
  ],
  status: 'active',
  responseCount: 0,
  createdAt: new Date()
};

// Trigger survey after order
export const triggerPostPurchaseSurvey = async (orderId: string) => {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { customer: true }
  });

  // Check if already sent
  const existingSurvey = await prisma.surveyInvitation.findFirst({
    where: { orderId, surveyId: 'post-purchase' }
  });

  if (existingSurvey) return;

  // Send survey invitation
  await sendSurveyInvitation({
    surveyId: 'post-purchase',
    customerId: order.customerId,
    orderId,
    channel: order.customer.preferredChannel
  });
};
```

## Components

### SurveyForm

```tsx
const SurveyForm = ({ survey, onSubmit }: SurveyFormProps) => {
  const form = useForm<SurveyFormData>();

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
      {survey.questions.map((question) => (
        <div key={question.id} className="space-y-2">
          <Label>
            {question.question}
            {question.required && <span className="text-red-500">*</span>}
          </Label>

          {question.type === 'rating' && (
            <RatingInput
              scale={question.scale}
              {...form.register(question.id, { required: question.required })}
            />
          )}

          {question.type === 'nps' && (
            <NPSInput {...form.register(question.id, { required: question.required })} />
          )}

          {question.type === 'text' && (
            <Textarea {...form.register(question.id, { required: question.required })} />
          )}

          {question.type === 'choice' && (
            <RadioGroup {...form.register(question.id, { required: question.required })}>
              {question.options?.map(opt => (
                <RadioGroupItem key={opt} value={opt}>{opt}</RadioGroupItem>
              ))}
            </RadioGroup>
          )}
        </div>
      ))}

      <Button type="submit">Submit Feedback</Button>
    </form>
  );
};

const RatingInput = ({ scale, value, onChange }: RatingInputProps) => (
  <div className="flex gap-1">
    {Array.from({ length: scale }, (_, i) => i + 1).map(n => (
      <button
        key={n}
        type="button"
        onClick={() => onChange(n)}
        className={cn(
          "w-10 h-10 rounded border",
          value === n ? "bg-primary text-white" : "hover:bg-muted"
        )}
      >
        {n}
      </button>
    ))}
  </div>
);

const NPSInput = ({ value, onChange }: NPSInputProps) => (
  <div className="space-y-2">
    <div className="flex justify-between text-sm text-muted-foreground">
      <span>Not likely</span>
      <span>Very likely</span>
    </div>
    <div className="flex gap-1">
      {Array.from({ length: 11 }, (_, i) => i).map(n => (
        <button
          key={n}
          type="button"
          onClick={() => onChange(n)}
          className={cn(
            "w-8 h-8 rounded text-sm",
            value === n
              ? n <= 6 ? "bg-red-500 text-white"
              : n <= 8 ? "bg-yellow-500 text-white"
              : "bg-green-500 text-white"
              : "border hover:bg-muted"
          )}
        >
          {n}
        </button>
      ))}
    </div>
  </div>
);
```

### SupportTicketForm

```tsx
const SupportTicketForm = ({ customerId, orderId }: SupportTicketFormProps) => {
  const form = useForm<CreateTicketData>();
  const { mutate: createTicket, isLoading } = useMutation({
    mutationFn: (data: CreateTicketData) =>
      fetch('/api/crm/tickets', {
        method: 'POST',
        body: JSON.stringify(data)
      }).then(r => r.json())
  });

  return (
    <form onSubmit={form.handleSubmit(data => createTicket(data))}>
      <div className="space-y-4">
        <div>
          <Label>Category</Label>
          <Select {...form.register('category', { required: true })}>
            <SelectItem value="order">Order Issue</SelectItem>
            <SelectItem value="product">Product Question</SelectItem>
            <SelectItem value="payment">Payment Issue</SelectItem>
            <SelectItem value="delivery">Delivery Issue</SelectItem>
            <SelectItem value="return">Return/Refund</SelectItem>
            <SelectItem value="other">Other</SelectItem>
          </Select>
        </div>

        <div>
          <Label>Subject</Label>
          <Input {...form.register('subject', { required: true })} />
        </div>

        <div>
          <Label>Description</Label>
          <Textarea
            rows={5}
            {...form.register('description', { required: true })}
          />
        </div>

        <div>
          <Label>Attachments (optional)</Label>
          <FileUpload
            accept="image/*,.pdf"
            maxFiles={3}
            onUpload={(files) => form.setValue('attachments', files)}
          />
        </div>

        <Button type="submit" disabled={isLoading}>
          {isLoading ? 'Submitting...' : 'Submit Ticket'}
        </Button>
      </div>
    </form>
  );
};
```

### TicketChat

```tsx
const TicketChat = ({ ticket }: { ticket: SupportTicket }) => {
  const [message, setMessage] = useState('');
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const { mutate: sendMessage } = useMutation({
    mutationFn: (content: string) =>
      fetch(`/api/crm/tickets/${ticket.id}/messages`, {
        method: 'POST',
        body: JSON.stringify({ content })
      })
  });

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [ticket.messages]);

  return (
    <div className="flex flex-col h-[500px]">
      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {ticket.messages.map((msg) => (
          <div
            key={msg.id}
            className={cn(
              "max-w-[80%] p-3 rounded-lg",
              msg.sender === 'customer'
                ? "ml-auto bg-primary text-white"
                : "bg-muted"
            )}
          >
            <p>{msg.content}</p>
            <p className="text-xs opacity-70 mt-1">
              {formatTime(msg.createdAt)}
            </p>
          </div>
        ))}
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      {ticket.status !== 'closed' && (
        <div className="border-t p-4">
          <div className="flex gap-2">
            <Input
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Type a message..."
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  sendMessage(message);
                  setMessage('');
                }
              }}
            />
            <Button onClick={() => {
              sendMessage(message);
              setMessage('');
            }}>
              <Send className="h-4 w-4" />
            </Button>
          </div>
        </div>
      )}
    </div>
  );
};
```

## Review Widget

```tsx
const ReviewWidget = ({ productId }: { productId: string }) => {
  const { data } = useQuery({
    queryKey: ['product-reviews', productId],
    queryFn: () => fetch(`/api/products/${productId}/reviews`).then(r => r.json())
  });

  return (
    <div className="space-y-4">
      {/* Summary */}
      <div className="flex items-center gap-4">
        <div className="text-center">
          <p className="text-4xl font-bold">{data?.averageRating.toFixed(1)}</p>
          <StarRating value={data?.averageRating} readonly size="sm" />
          <p className="text-sm text-muted-foreground">
            {data?.totalReviews} reviews
          </p>
        </div>

        <div className="flex-1">
          {[5, 4, 3, 2, 1].map(star => (
            <div key={star} className="flex items-center gap-2">
              <span className="w-4">{star}</span>
              <Progress
                value={(data?.ratingDistribution[star] / data?.totalReviews) * 100}
                className="h-2"
              />
              <span className="w-8 text-sm text-muted-foreground">
                {data?.ratingDistribution[star]}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Reviews list */}
      <div className="space-y-4">
        {data?.reviews.map((review: ProductReview) => (
          <div key={review.id} className="border rounded p-4">
            <div className="flex items-center gap-2 mb-2">
              <StarRating value={review.rating} readonly size="sm" />
              {review.isVerified && (
                <Badge variant="secondary">Verified Purchase</Badge>
              )}
            </div>
            {review.title && (
              <p className="font-medium">{review.title}</p>
            )}
            <p className="text-sm">{review.content}</p>
            <p className="text-xs text-muted-foreground mt-2">
              {formatDate(review.createdAt)}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
};
```
