# Source Scan: Billing / Subscription Management UI

**Source:** /Volumes/Ext-nvme/Development/subsheroload
**Scanned:** 2026-03-21
**Stack:** Laravel 12.x + React 19.x (via Inertia.js)

---

## Tech Stack Summary

- **Backend:** Laravel 12.x (PHP 8.3+)
- **Frontend:** React 19.x via Inertia.js (`@inertiajs/react` ^2.3.11)
- **Database:** MySQL (primary), SQLite (dev)
- **Payment:** Stripe + PayPal (via `omnipay/stripe`, `omnipay/paypal`)
- **Auth:** Laravel Sanctum
- **State (frontend):** Zustand (global store for usage/plan data), local `useState` for UI state
- **Data fetching:** Raw `fetch()` calls (no TanStack Query or SWR)
- **Invoices:** `elegantly/laravel-invoices` package (server-side PDF generation)
- **CSS:** Tailwind v4 + shadcn/ui (Radix UI primitives)
- **Icons:** Lucide React + Tabler Icons
- **Toast:** Sonner
- **Frontend communicates with backend via:** Inertia.js page props (initial data) + direct `fetch()` REST API calls for mutations and live data

---

## Backend

### Routes

| Method | URL | Controller | Middleware |
|---|---|---|---|
| GET | /app/settings/billing | Inertia render `app/billing/index` | `auth` |
| GET | /api/user/subscription/plans | SubscriptionController@getAvailablePlans | `auth` |
| POST | /api/user/subscription/upgrade | SubscriptionController@processUpgrade | `auth` |
| POST | /api/user/subscription/cancel | SubscriptionController@cancelSubscription | `auth` |
| POST | /api/user/subscription/payment/callback | SubscriptionController@handlePaymentCallback | `auth` |
| POST | /api/user/subscription/payment/complete | SubscriptionController@completePayment | `auth` |
| POST | /api/user/subscription/manual-complete | SubscriptionController@manualCompleteOrder | `auth` |
| POST | /api/user/subscription/webhook/paypal | SubscriptionController@handlePaymentCallback | (public) |
| GET | /api/user/invoices | InvoiceController@index | `auth` |
| GET | /api/user/invoices/{serial} | InvoiceController@show | `auth` |
| GET | /api/user/invoices/{serial}/download | InvoiceController@download | `auth` |
| GET | /api/user/invoices/{serial}/view | InvoiceController@view | `auth` |
| POST | /api/user/invoices/{serial}/opened | InvoiceController@markAsOpened | `auth` |
| GET | /api/user/usage | (UserUsageController) | `auth` |

### Controllers

#### SubscriptionController (`App\Http\Controllers\Api\User\SubscriptionController`)

- **`getAvailablePlans()`** — Returns `ShopPlan::whereIn('id', [2,4,6])->where('status', true)->orderBy('sort')`. Returns `{ success, data: [...plans], message }`.
- **`processUpgrade(Request $request)`** — Validates `plan_id`, `billing_cycle` (monthly|annually), `payment_method` (stripe|paypal), `return_url`, `cancel_url`. Calculates amount from `plan->price_annually` or `plan->price_monthly`. Creates/gets `ShopCustomer`, creates `ShopOrder`, then routes to `processPayPalPayment()` or `processStripePayment()`. Returns redirect URL for the payment gateway. Wraps in DB transaction.
- **`completePayment(Request $request)`** — Validates `order_id`, `payment_id`, `payer_id`. Finds order by `number` field. Verifies order belongs to current user. Calls `completeOrderPayment()`, then `activateSubscription()`, then `invoiceService->createInvoiceFromOrder()`. Returns subscription response data.
- **`cancelSubscription(Request $request)`** — Finds `UserPlan` for current user (bypasses global scope). If already on free plan (ID 1), returns success. Attempts to cancel PayPal subscription if applicable. Updates `UserPlan->plan_id` to free plan (ID 1). Resets usage counters via `ShopPlan::find(1)`.
- **`manualCompleteOrder(Request $request)`** — Admin/debug endpoint to force-complete a pending order and activate subscription.
- **`handlePaymentCallback()`** — PayPal webhook handler.

#### InvoiceController (`App\Http\Controllers\Api\InvoiceController`)

- **`index()`** — Returns paginated `ShopInvoice` list for current user, with items eager loaded.
- **`show($serial)`** — Returns single invoice with items.
- **`download($serial)`** — Streams PDF. Uses `elegantly/laravel-invoices` for PDF generation.
- **`view($serial)`** — Opens PDF inline in browser.
- **`markAsOpened($serial)`** — Sets `email_opened_at` timestamp.

### Models & Schema

#### ShopPlan (table: `shop_plans`)

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| name | string | |
| slug | string | |
| description | text | |
| type | string | `free` \| `paid` \| `lifetime` |
| plan_type | string | `individual` \| `team` |
| price_monthly | decimal(10,2) | |
| price_annually | decimal(10,2) | |
| ltd_price | decimal(10,2) | nullable |
| ltd_price_date | date | nullable |
| currency | string | default USD |
| limit_subs | integer | -1 = unlimited |
| limit_folders | integer | |
| limit_tags | integer | |
| limit_contacts | integer | |
| limit_pmethods | integer | |
| limit_alert_profiles | integer | |
| limit_webhooks | integer | |
| limit_teams | integer | |
| limit_storage | integer | MB |
| is_default | boolean | |
| is_upgradable | boolean | |
| trial_days | integer | |
| number_of_users | integer | |
| sort | integer | ordering |
| status | boolean | |
| product_id | FK nullable | |
| variation_id | FK nullable | |
| features | json | array of feature strings |
| ai_invoice_monthly_limit | integer | nullable, AI credits |

#### UserPlan (table: `users_plans`) — the user-plan assignment + usage counters

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| user_id | FK → users | |
| plan_id | FK → shop_plans | current assigned plan |
| total_subs | integer | current usage count |
| total_folders | integer | |
| total_tags | integer | |
| total_contacts | integer | |
| total_pmethods | integer | |
| total_alert_profiles | integer | |
| total_webhooks | integer | |
| total_teams | integer | |
| total_storage | integer | |
| grace_period_active | boolean | |
| grace_period_started_at | datetime | nullable |
| grace_period_expires_at | datetime | nullable |
| limit_exceeded_features | json | array |
| account_disabled | boolean | |
| account_disabled_at | datetime | nullable |
| account_disabled_reason | string | nullable |

Note: Global scope auto-filters by `Auth::id()`. Controller must use `withoutGlobalScope('user')` when searching by user_id explicitly.

#### ShopOrder (table: `shop_orders`)

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| shop_customer_id | FK → shop_customers | |
| shop_plan_id | FK → shop_plans | |
| number | string | unique order reference |
| total_price | decimal(10,2) | |
| original_price | decimal(10,2) | before discount |
| discount_amount | decimal(10,2) | |
| status | string | pending/completed/cancelled |
| currency | string | |
| payment_method | string | stripe/paypal |
| payment_id | string | gateway payment/subscription ID |
| payment_status | string | pending/completed/failed |
| transaction_id | string | nullable |
| coupon_id | FK nullable | |
| notes | text | nullable |
| deleted_at | timestamp | SoftDeletes |

#### ShopInvoice (table: `shop_invoices`) — extends `elegantly/laravel-invoices` BaseInvoice

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| user_id | FK → users | |
| shop_order_id | FK → shop_orders | |
| invoice_number | string | human-readable number |
| serial_number | string | unique identifier for URLs |
| status | string | pending/generated/sent/paid/cancelled/failed |
| type | string | |
| currency | string | |
| subtotal | decimal(10,2) | |
| tax_amount | decimal(10,2) | |
| discount_amount | decimal(10,2) | |
| total | decimal(10,2) | |
| billing_period_start | date | |
| billing_period_end | date | |
| due_date | date | |
| pdf_path | string | nullable, relative path to generated PDF |
| pdf_generated_at | datetime | nullable |
| email_sent_at | datetime | nullable |
| email_opened_at | datetime | nullable |
| paid_at | datetime | nullable |

Note: Invoice PDF generation is handled by `InvoiceGenerationService` using the `elegantly/laravel-invoices` package. ShopInvoice extends the package's `BaseInvoice` model with custom fields.

#### ShopCustomer (table: `shop_customers`)
- Bridge between `User` and `ShopOrder`. Created on first purchase via `createOrGetCustomer()`.
- Fields: `user_id`, `name`, `email`, gateway customer IDs.

### Services

#### PaymentGatewayConfigService
- Loads gateway credentials (Stripe/PayPal) from DB config (not hardcoded env).
- Used in `SubscriptionController` to build Omnipay gateway instances.
- Admin can configure active gateway via `/admin/payment-settings/gateways`.

#### InvoiceGenerationService
- `createInvoiceFromOrder(ShopOrder $order): ShopInvoice` — Creates `ShopInvoice` record and generates PDF.
- Called after successful payment completion.
- Invoice creation failure is non-blocking (caught and logged, payment proceeds).

### Key Business Logic (Backend)

- **Plan assignment:** `users_plans.plan_id` = current plan. Changing plan = updating this row. Plan ID 1 = free plan.
- **Subscription activation:** `activateSubscription(ShopOrder $order)` updates `UserPlan->plan_id` and resets/upgrades usage counters.
- **Billing cycle:** Stored on `ShopOrder` implicitly via `total_price` matching `price_monthly` or `price_annually`. Also stored as metadata in the subscription response.
- **Renewal date:** Computed from order completion date + 1 month or 1 year. Stored in the usage API response as `subscription.next_renewal_date`.
- **Cancel = downgrade to free:** No grace period on manual cancel. Immediate downgrade to plan ID 1.
- **PayPal subscriptions:** Attempted cancellation via PayPal API on cancel. Failure is non-blocking.
- **Coupons:** `ShopCoupon`/`ShopCouponUsage` tables. Applied at checkout. Discount reflected in `ShopOrder.discount_amount`.

---

## Frontend

### Pages

| Route | Component File | Layout |
|---|---|---|
| /app/settings/billing | `resources/js/pages/app/billing/index.tsx` | UserLayout + UserSidebar + UserHeader |

The `index.tsx` is a thin shell. It lazy-loads `billing-content.tsx` via `React.lazy()` + `Suspense` to prevent SSR hydration issues.

### Components

#### `billing-content.tsx` (main page component)
- Fetches current plan from `/api/user/usage` on mount via raw `fetch()`
- Fetches invoices via `useInvoices()` hook
- Fetches shop plans via `useUserShopPlans()` hook
- **State:**
  - `currentPlan` — `{ id, name, type, price_monthly, price_annually, currency }`
  - `currentSubscription` — `{ billing_cycle, current_price, next_renewal_date, status }`
  - `isUpgradeModalOpen`, `isCancelDialogOpen`, `showPaymentSuccess`
  - `initialCouponCode`, `initialPlanId` — from URL params for promotion banner flow
  - `paymentSuccessData` — shown in success dialog after PayPal return
- **Layout:** 2-column grid (`lg:grid-cols-2`):
  - Left: Current Plan card + Usage Metrics card
  - Right: Plan Details card (name, billing cycle, price, currency, renewal date, status, pricing options) + Billing History card

#### Current Plan Card (inside `billing-content.tsx`)
```
Card
  Package icon + plan name + "Current Plan" badge
  Subtitle: price/interval + renewal date (for paid) | "Free plan..." (for free)
  Buttons (conditional):
    - Free plan: "Upgrade Plan" button (outline)
    - Team member: "Plan managed by team owner" text
    - Paid plan: "Change Plan" (outline) + "Cancel Plan" (destructive)
```

#### Plan Details Card (inside `billing-content.tsx`)
```
Card
  h3: "Plan Details"
  Key-value rows: Plan Name | Billing Cycle | Current Price | Currency | Next Renewal | Status (Badge)
  If paid: Pricing Options section (monthly price | annual price | annual savings in green)
```

#### Billing History Card (inside `billing-content.tsx`)
```
Card
  h3: "Billing History" + "Download All" button
  For each invoice:
    FileText icon + Invoice #number + date
    Badge (status) + currency+total
    Eye button (view) + Download button (if pdf_path exists)
  Empty state: FileText icon + "No invoices yet"
```

#### `PlanUpgradeModal.tsx` — Multi-step modal for plan change
- Steps: `plan-selection` → `order-summary` → `payment-method` → `payment-processing` → `confirmation`
- Props: `open`, `onClose`, `currentUserPlan: UserSubscription | null`, `availablePlans: ShopPlan[]`, `onUpgradeComplete`, `initialCouponCode`, `initialPlanId`
- Uses `Dialog` from shadcn/ui
- Progress bar showing step advancement

#### `PlanSelectionCard.tsx` — Step 1 of modal
- Filters plans: excludes `type === 'free'`, separates individual vs team by `plan_type`
- Toggle for individual/team plan type (User/Users icon)
- Monthly/annually billing toggle (Switch)
- Feature list auto-generated from `limit_*` fields + `features` JSON field
- Highlights recommended plan with Star icon

#### `OrderSummaryStep.tsx` — Step 2 of modal
- Shows selected plan, billing cycle, price, coupon input, final total

#### `PaymentProcessingStep.tsx` — Step 4 of modal
- Calls `POST /api/user/subscription/upgrade` with `{ plan_id, billing_cycle, payment_method, return_url, cancel_url }`
- On success: redirects to PayPal/Stripe checkout URL

#### `ConfirmationStep.tsx` — Step 5 of modal (on-site payment gateway only)
- Shows transaction details

#### `InvoiceHistory.tsx` — Standalone reusable component (not used in main page directly; inline version in billing-content.tsx is used instead)
- Props: `invoices[]`, `loading`, `onDownload`, `onView`, `onRefresh`
- Status badge color map: pending=yellow, generated=blue, sent=green, paid=emerald, cancelled=gray, failed=red
- Only shows download/view buttons when `pdf_path` is set AND status is generated/sent/paid

### Hooks

#### `useInvoices()` (`resources/js/hooks/useInvoices.tsx`)
- Fetches `GET /api/user/invoices` on mount
- Returns: `{ invoices, loading, error, fetchInvoices, downloadInvoice, viewInvoice }`
- `downloadInvoice(serial)` — creates `<a>` element, triggers download from `/api/user/invoices/{serial}/download`
- `viewInvoice(serial)` — `window.open(/api/user/invoices/{serial}/view, '_blank')`

#### `useUserShopPlans()` (`resources/js/hooks/use-user-shop-plans.ts`)
- Fetches available plans from the user-facing plans API
- Returns: `{ plans: ShopPlan[], loading, error }`

#### `useUsageStore` (Zustand store)
- Contains: `metrics`, `loading`, `error`, `lastRefresh`
- Actions: `fetchUsage()`, `refreshUsage()`, `fetchSummary()`
- Used for usage metric cards on billing page

### API Calls (Frontend → Backend)

| Component | Endpoint | Method | Purpose |
|---|---|---|---|
| billing-content | `GET /api/user/usage` | fetch | Get current plan + subscription + renewal date |
| billing-content | `POST /api/user/subscription/cancel` | fetch | Cancel plan → downgrade to free |
| billing-content | `POST /api/user/subscription/payment/complete` | fetch | Complete PayPal return (with order_id, payment_id, payer_id) |
| useInvoices | `GET /api/user/invoices` | fetch | List invoices (paginated) |
| useInvoices | `GET /api/user/invoices/{serial}/download` | anchor href | Download PDF |
| useInvoices | `GET /api/user/invoices/{serial}/view` | window.open | View PDF in browser |
| PlanUpgradeModal | `GET /api/user/subscription/plans` | fetch | Load available plans |
| PaymentProcessingStep | `POST /api/user/subscription/upgrade` | fetch | Initiate payment → get redirect URL |

### URL Parameter Handling (Billing Page)
On mount, billing-content reads URL params to handle:
- `?order_id=X&paymentId=Y&PayerID=Z&payment=success` → auto-completes PayPal payment
- `?coupon=CODE` → opens upgrade modal with pre-filled coupon
- `?plan=ID` → pre-selects plan in upgrade modal

### Styling Patterns
- Tailwind v4 utility classes throughout
- 2-column responsive grid: `grid grid-cols-1 gap-6 lg:grid-cols-2`
- `Card` + `CardContent` with `p-6` padding
- Key-value rows: `flex justify-between` with `text-muted-foreground text-sm` label and `text-sm font-medium` value
- Status badges: `Badge variant="outline" className="capitalize"`
- Loading spinners: `border-primary h-8 w-8 animate-spin rounded-full border-b-2`
- Error state: `rounded-lg border border-red-200 bg-red-50 p-4` with `AlertTriangle` icon
- Invoice item row: `flex ... border-b py-3 last:border-0`

---

## Business Logic

### User Flows

#### 1. View Billing Page
1. Page loads, `fetchUsage()` and `fetchCurrentPlan()` called simultaneously
2. Current plan card shows: plan name, badge, subtitle with price/renewal
3. Plan Details card shows key-value breakdown
4. Invoices loaded via `useInvoices()` hook, shown in Billing History card

#### 2. Upgrade / Change Plan
1. User clicks "Upgrade Plan" or "Change Plan" → `PlanUpgradeModal` opens at `plan-selection` step
2. User selects individual/team type, monthly/annual cycle, chooses a plan
3. Proceeds to `order-summary` → can apply coupon
4. Proceeds to `payment-method` → selects Stripe or PayPal
5. Proceeds to `payment-processing` → frontend calls `POST /api/user/subscription/upgrade`
6. Backend creates `ShopCustomer` (if new), creates `ShopOrder`, initiates payment with Omnipay
7. Frontend receives redirect URL, redirects user to payment gateway
8. After payment, gateway redirects back to `/app/settings/billing?order_id=X&paymentId=Y&PayerID=Z&payment=success`
9. Page mount effect detects params, calls `POST /api/user/subscription/payment/complete`
10. Backend verifies payment, calls `activateSubscription()`, generates invoice
11. Frontend shows success dialog with plan name, amount, billing cycle, transaction ID

#### 3. Cancel Plan
1. User clicks "Cancel Plan" → `Dialog` opens with confirmation
2. User confirms → `POST /api/user/subscription/cancel`
3. Backend downgrades `UserPlan.plan_id` to 1 (free), attempts PayPal subscription cancel
4. Toast success + page reload after 2 seconds

#### 4. Download Invoice
1. Invoices listed with status badges
2. If `pdf_path` set and status is generated/sent/paid: View and Download buttons shown
3. Download creates anchor element with `/api/user/invoices/{serial}/download` href

### Edge Cases
- **PayPal return with missing payment_id:** URL params `order_id` present but `paymentId` absent — logged as error, no auto-complete triggered
- **Cancel on free plan:** Server returns success immediately: "You are already on the Free plan"
- **Team member plan:** `type === 'team_member'` — no upgrade/cancel buttons shown, text says "Plan managed by team owner"
- **Invoice PDF not yet generated:** Download/View buttons hidden; "Generating..." badge shown for pending status
- **Invoice generation failure:** Non-blocking — payment succeeds even if invoice PDF generation fails
- **PayPal subscription cancel failure:** Non-blocking — plan still downgraded to free even if PayPal API call fails
- **Payment gateway config from DB:** Not hardcoded env vars — admin configures via payment settings UI; graceful failure if unconfigured

### Permissions
- All billing routes require `auth` middleware (authenticated user)
- Users can only view/cancel their own subscription (controller verifies `order->customer->user_id === Auth::id()`)
- Team members cannot change/cancel plan (frontend hides buttons; no server-side enforcement found for this edge case)
- Admin can access all subscription management via separate admin routes with `force_complete` flag

---

## Required Environment Variables

| Var Name | Purpose | Required/Optional | Target Env.ts Mapping |
|---|---|---|---|
| STRIPE_SECRET_KEY | Stripe server-side API key | Required for Stripe payments | `STRIPE_SECRET_KEY` (check Env.ts) |
| STRIPE_PUBLISHABLE_KEY | Stripe client-side key | Required for Stripe | `STRIPE_PUBLISHABLE_KEY` (check Env.ts) |
| STRIPE_WEBHOOK_SECRET | Stripe webhook verification | Optional (for webhooks) | — |
| STRIPE_TEST_MODE | Toggle Stripe sandbox | Optional | — |
| PAYPAL_CLIENT_ID | PayPal app client ID | Required for PayPal | — (new, add to Env.ts) |
| PAYPAL_CLIENT_SECRET | PayPal app secret | Required for PayPal | — (new, add to Env.ts) |
| PAYPAL_SANDBOX | Toggle PayPal sandbox | Optional | — |

Note: In subsheroload, gateway credentials are stored in a DB table (`payment_gateway_configs`) and loaded via `PaymentGatewayConfigService`. The env vars serve as fallback defaults. Our target app (nyayasathi) currently uses Razorpay; PayPal/Stripe are different gateways and would need separate integration.

---

## Shared Dependencies (Out of Scope for this UI port)

- **Usage metrics cards (`UsageMetricCard`, `useUsageStore`)** — used by billing page AND dashboard. Port separately.
- **Promotion banner (`PromotionBanner`)** — used by billing AND other pages. Port separately.
- **Coupon system (`CouponInput`, `ShopCoupon`)** — used by checkout AND billing. Port separately.
- **Payment gateway service** — entire Stripe/PayPal Omnipay integration. Already exists in nyayasathi as Razorpay. Scope: adapt billing page to call existing payment procedures; do not port payment gateway.
- **`UserPlan` / `users_plans` table** — maps to nyayasathi's existing subscription/org model. Coordinate with auth migration.

---

## What Is In Scope (UI Port Only)

The user's stated goal is to port the **design/UI** of the billing page. The target app already has billing backend logic (Razorpay, existing subscription schema). The in-scope work is:

1. **Current Plan Card** — plan name, status badge, price + interval + renewal date, conditional Change/Cancel buttons
2. **Plan Details Card** — key-value breakdown (name, billing cycle, price, currency, renewal, status)
3. **Billing History Card** — invoice list with status badge, amount, view/download actions, empty state
4. **Cancel Confirmation Dialog** — AlertTriangle icon, plan name, warning text, Keep/Cancel buttons
5. **Payment Success Dialog** — CheckCircle2 icon, plan/amount/cycle/transaction details
6. **Page layout** — 2-column responsive grid with left (plan info + usage) / right (details + history) structure
