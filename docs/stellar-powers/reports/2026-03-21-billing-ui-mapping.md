# Feature Mapping: Billing / Subscription Management UI

**Source:** /Volumes/Ext-nvme/Development/subsheroload (Laravel 12.x + React via Inertia.js)
**Target:** /Users/rohits/dev/nyayasathi-app (Next.js + oRPC + Drizzle)
**Mapped:** 2026-03-21

---

## Scope Reminder

The goal is a **UI port only**. The target already has a complete billing backend (Razorpay + Stripe, subscription schema, invoices, oRPC procedures). The work is bringing the source's richer page design into the target's existing component architecture.

---

## Backend Mapping

| Source (Laravel) | Target (oRPC) | Status | Adaptation Notes |
|---|---|---|---|
| `SubscriptionController@getAvailablePlans` | `router.billing.getPlans` | ✅ Exists | Target filters by `type` (client/lawyer). Source hardcodes IDs [2,4,6]. Target pattern is strictly better — no change needed. |
| `SubscriptionController@processUpgrade` | `router.billing.createCheckout` | ✅ Exists | Source initiates redirect to PayPal/Stripe. Target opens Razorpay overlay or redirects for Stripe. Same intent, different UX flow. |
| `SubscriptionController@cancelSubscription` | `router.billing.cancel` | ✅ Exists | Source: immediate downgrade to plan ID 1 (free). Target: `cancelAtPeriodEnd = true` (softer cancel). **Behaviour difference** — target is already better. No change. |
| `SubscriptionController@completePayment` | N/A — webhook-driven | ✅ Covered | Target activates via webhook (idempotent `webhookEvent` table). Source used a manual `POST /payment/complete` after PayPal redirect. Target approach is better. |
| `SubscriptionController@manualCompleteOrder` | N/A | Skip | Admin debug endpoint. No equivalent needed. |
| `SubscriptionController@handlePaymentCallback` | `src/app/api/webhooks/` | ✅ Exists | PayPal webhook only in source. Target has Razorpay + Stripe webhooks. |
| `InvoiceController@index` | `router.billing.getInvoices` | ✅ Exists | Source returns paginated `ShopInvoice` with `serial_number`, `pdf_path`. Target returns invoices without PDF path (no server-side PDF generation). See Schema Mapping for gaps. |
| `InvoiceController@download` / `@view` | — | ❌ Not present | Target has no PDF download/view. Source invoices have `pdf_path`. **In-scope for UI port as a display gap** — target should show `providerInvoiceId` as a link when available, not attempt to serve PDFs. |
| `GET /api/user/usage` | `router.billing.getSubscription` | ✅ Covered | Source's `/usage` also returned renewal date, current price. Target's `getSubscription` returns `currentPeriodEnd`, `billingInterval`, `planId`. Same data, different field names. |
| `router.billing.reactivate` | `router.billing.reactivateSubscription` | ✅ Exists | Source never had reactivation (cancel = immediate downgrade). Target already has this. UI port can expose reactivation — it's already wired in `BillingPageClient`. |
| `router.billing.portal` | `router.billing.getBillingPortal` | ✅ Exists | Stripe Customer Portal URL. No equivalent in source. Already in target. |

---

## Frontend Mapping

| Source Component | Target Component | Status | Adaptation Notes |
|---|---|---|---|
| `billing-content.tsx` (main shell) | `BillingPageClient.tsx` (both `/client/billing/` and `/dashboard/billing/`) | ✅ Exists | Target already has the client shell with polling, cancel dialog, checkout dialog. **Gap:** target layout is vertical stack (SubscriptionCard → PaymentHistoryTable → PricingSection). Source is 2-column grid (plan info left, details + history right). The source design adds a **Plan Details Card** (key-value breakdown) that the target lacks. |
| Current Plan Card (inside `billing-content.tsx`) | `SubscriptionCard.tsx` | ✅ Exists | Target has plan name, status badge, price, interval, renewal/cancel date, Cancel/Reactivate buttons. **Gap:** source shows "Package" icon + plan type badge + subtitle with currency. Target shows provider label instead. Minor styling differences. |
| Plan Details Card (inside `billing-content.tsx`) | — | ❌ Missing | Source has a dedicated key-value card: Plan Name / Billing Cycle / Current Price / Currency / Next Renewal / Status. Target has none of this — `SubscriptionCard` shows a collapsed version. **This is the primary new component to add.** |
| Billing History Card (inside `billing-content.tsx`) | `PaymentHistoryTable.tsx` | ✅ Exists | Target renders a `<Table>`. Source renders a card with list rows and View/Download icon buttons per invoice. **Gap:** source shows View and Download buttons per row when `pdf_path` is set. Target has no per-row actions. Since target has no PDF generation, adapt to: show `providerInvoiceId` as an external link when available. Also, source has "Download All" header button — skip (no PDFs in target). |
| `PlanUpgradeModal.tsx` (multi-step: plan-selection → order-summary → payment-method → processing → confirmation) | `CheckoutDialog.tsx` (summary → processing → confirmed) | ✅ Exists (simpler) | Source is a 5-step wizard including plan selection inside the modal. Target keeps plan selection on the page (`PricingSection`) and only opens `CheckoutDialog` for checkout itself (3 states). Target approach is cleaner. **No change to flow.** UI styling improvements from source can be applied to `CheckoutSummary`. |
| `PlanSelectionCard.tsx` (step 1 of modal) | `PlanCard.tsx` + `PricingSection.tsx` | ✅ Exists | Source separates individual/team via toggle, derives features from `limit_*` fields + `features` JSON. Target derives features from `limits` JSON (same idea). Source has Star icon for recommended. Target uses `popular` badge. Target also supports hardcoded `planDescriptions` per plan ID. **Gap:** source has individual/team plan type toggle — target does not (plans are already pre-filtered by user type via `getPlans({ type })`). No change needed. |
| `OrderSummaryStep.tsx` (step 2: coupon input, final total) | `CheckoutSummary.tsx` | ✅ Exists (simpler) | Target shows plan name, price, total. No coupon input. Source had coupon input — out of scope per source scan. |
| `PaymentProcessingStep.tsx` (step 4) | `CheckoutSummary.tsx` → `RazorpayCheckout.tsx` | ✅ Exists | Source redirects to PayPal/Stripe. Target opens Razorpay overlay or redirects for Stripe. Different gateway but same UX intent. |
| `ConfirmationStep.tsx` (step 5) | `OrderConfirmation.tsx` | ✅ Exists | Source showed transaction ID, plan, amount, billing cycle. Target shows plan name + generic success. **Gap:** target `OrderConfirmation` lacks amount/cycle/transaction details in confirmation. Minor improvement opportunity. |
| Cancel Confirmation Dialog | `CancelSubscriptionDialog.tsx` | ✅ Exists | Source: `AlertTriangle` icon, plan name, immediate downgrade warning. Target: reason dropdown, `periodEnd` shown, cancel-at-period-end semantics. Target is more sophisticated. **Gap:** source had `AlertTriangle` icon and explicit "you'll lose access" warning text. Target lacks icon and warning severity. Minor visual improvement. |
| Payment Success Dialog (shown after PayPal return) | `CheckoutDialog` `confirmed` state | ✅ Exists | Source detected URL params (`?payment=success&order_id=X&paymentId=Y&PayerID=Z`) and called `completePayment`. Target detects `?status=processing` and polls `getSubscription`. Different mechanism, same outcome. |
| `InvoiceHistory.tsx` (standalone, unused on main page) | — | Skip | Source had an alternative standalone component that was not used in the main page. Target's `PaymentHistoryTable` covers it. |
| `useInvoices()` hook | oRPC client call in `BillingPageClient` | ✅ Covered | Target fetches invoices server-side and passes as props. No client-side hook needed. |
| `useUserShopPlans()` hook | oRPC client call / server-side fetch | ✅ Covered | Same as above. |
| `useUsageStore` (Zustand) | — | Skip (out of scope) | Usage metrics cards are a shared dependency. Port separately. |
| Page layout (2-column responsive grid) | Vertical stack | Partial gap | Source: `grid grid-cols-1 gap-6 lg:grid-cols-2`. Target: vertical stack. The **2-column layout is in-scope** to port since it's purely presentational. |

---

## Schema Mapping

| Source Table | Target Table | Status | Column Diff |
|---|---|---|---|
| `shop_plans` | `plan` | ✅ Exists | Source has `type` (free/paid/lifetime), `plan_type` (individual/team), `limit_*` fields, `features` JSON, `sort`, `status`, `trial_days`, `ai_invoice_monthly_limit`. Target has `type` (client/lawyer), `limits` JSONB, Stripe/Razorpay price IDs. **Key difference:** source embeds all limit fields as top-level columns; target uses single `limits` JSONB. Target pattern is better. Source has `features` JSON separate from limits; target merges all into `limits`. No schema change needed. |
| `users_plans` | `subscription` | ✅ Exists | Source: plan assignment + usage counters + grace period + account_disabled. Target: subscription lifecycle (status, billingInterval, cancelAtPeriodEnd, currentPeriodEnd, trialEnd). Target does not track usage counters — those are app-level features (out of scope). No schema change needed. |
| `shop_orders` | N/A | N/A | Source used `ShopOrder` as a checkout record before subscription activation. Target creates `subscription` row in pending state directly (via `createCheckout`), updated by webhook. Target approach is simpler and already complete. |
| `shop_invoices` | `invoice` | ✅ Exists | Source: `serial_number`, `invoice_number`, `status` (pending/generated/sent/paid/cancelled/failed), `pdf_path`, `pdf_generated_at`, `email_sent_at`, `email_opened_at`, `billing_period_start`, `billing_period_end`, `subtotal`, `tax_amount`, `discount_amount`. Target: `invoiceNumber`, `providerInvoiceId`, `plan`, `amount`, `currency`, `status`, `paidAt`. **Gap:** target `invoice` table lacks `billingPeriodStart`, `billingPeriodEnd`, `taxAmount`, `discountAmount`. These are not required for the UI port (none shown in source UI). Target also lacks `pdfPath` — intentional (no PDF generation). |
| `shop_customers` | N/A | N/A | Source created `ShopCustomer` bridge records. Target stores customer IDs directly on `subscription` table (`stripeCustomerId`, `razorpayCustomerId`). Target approach is simpler. |
| `webhook_event` | `webhookEvent` | ✅ Exists | Direct equivalent. |
| `organization_billing` | `organizationBilling` | ✅ Exists | Direct equivalent. |

---

## Missing in Target (New Work for UI Port)

1. **`PlanDetailsCard` component** — New component showing key-value breakdown: Plan Name, Billing Cycle, Current Price, Currency, Next Renewal Date, Status badge. Wraps the data already available from `getSubscription` + `getPlans`. Target has this data in `SubscriptionCard` but in a collapsed non-scannable form.

2. **2-column responsive page layout** — Both `BillingPageClient.tsx` files need layout updated to `grid grid-cols-1 gap-6 lg:grid-cols-2`: left column (SubscriptionCard + PlanDetailsCard), right column (PaymentHistoryTable). `PricingSection` stays full-width below.

3. **Per-invoice external link** — `PaymentHistoryTable.tsx` shows no actions per row. Source showed View/Download buttons when PDF was available. Since target has no PDF generation, adapt to show `providerInvoiceId` as a link to the provider portal when set.

4. **`OrderConfirmation` enrichment** — Add billing cycle and amount to the confirmation view (currently just shows plan name). Data is available from `CheckoutDialog` props.

5. **`CancelSubscriptionDialog` visual** — Add `AlertTriangle` icon and a more prominent warning ("You will lose access to [plan] features") before the reason dropdown.

---

## Exists but Needs Update

1. **`SubscriptionCard.tsx`** — Add Package/Shield icon next to plan name (source used Package icon). Replace provider label line with "Free plan..." subtitle when on free tier. Minor visual polish only.

2. **`PaymentHistoryTable.tsx`** — Add `providerInvoiceId` column with link when set. Source had `FileText` icon per row — can add for visual consistency. Also, "Provider" column header needs i18n key (currently hardcoded string).

3. **`PricingSection.tsx`** — Plan descriptions are currently hardcoded as a `Record<string, string>` inside the component. These should come from i18n or plan data. Not blocking but worth noting.

---

## Can Skip (Already Better in Target)

1. Source's URL param handling for PayPal (`?order_id=X&paymentId=Y&PayerID=Z`) — target uses cleaner `?status=processing` + webhook polling.
2. Source's `manualCompleteOrder` admin endpoint — no equivalent needed.
3. Source's coupon input in checkout — out of scope.
4. Source's individual/team toggle in plan selection — target pre-filters by user type server-side.
5. Source's `useUsageStore` / usage metric cards — shared dependency, port separately.
6. Source's `PromotionBanner` / `?coupon=CODE` / `?plan=ID` URL param pre-selection — out of scope.
7. Source's PDF generation, invoice download/view endpoints — target uses provider invoice IDs instead.
8. Source's PayPal gateway — target uses Razorpay + Stripe (already integrated). No env var additions needed.

---

## Environment Variables

| Source Var | Target Env.ts | Status | Notes |
|---|---|---|---|
| `STRIPE_SECRET_KEY` | `STRIPE_SECRET_KEY` | ✅ Exists | Already in `Env.ts` as optional. |
| `STRIPE_PUBLISHABLE_KEY` | `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | ✅ Exists | Already in `Env.ts`. |
| `STRIPE_WEBHOOK_SECRET` | `STRIPE_WEBHOOK_SECRET` | ✅ Exists | Already in `Env.ts`. |
| `PAYPAL_CLIENT_ID` | — | Skip | PayPal not used in target. |
| `PAYPAL_CLIENT_SECRET` | — | Skip | PayPal not used in target. |
| `RAZORPAY_KEY_ID` | `RAZORPAY_KEY_ID` / `NEXT_PUBLIC_RAZORPAY_KEY_ID` | ✅ Exists | Both server and client vars already defined. |
| `RAZORPAY_KEY_SECRET` | `RAZORPAY_KEY_SECRET` | ✅ Exists | Already in `Env.ts`. |
| `RAZORPAY_WEBHOOK_SECRET` | `RAZORPAY_WEBHOOK_SECRET` | ✅ Exists | Already in `Env.ts`. |

**No new env vars required for this UI port.**

---

## Conflict Resolution Decisions

1. **Cancel semantics mismatch** — Source cancels immediately (downgrade to free plan ID 1). Target cancels at period end (`cancelAtPeriodEnd = true`). **Decision: Keep target's approach.** It is strictly better UX. `CancelSubscriptionDialog` already shows the period end date. The warning text update (item 5 in Missing section) should reflect "at period end" semantics, not "immediate access loss."

2. **Invoice display without PDFs** — Source showed View/Download buttons per invoice row. Target has no PDF generation. **Decision: Show `providerInvoiceId` as an external link** when set (e.g. links to Stripe invoice URL or Razorpay dashboard). This satisfies the UX intent without server-side PDF infrastructure.

3. **Plan limits: top-level columns vs. JSONB** — Source had `limit_subs`, `limit_folders`, etc. as columns. Target uses `limits` JSONB. **Decision: Keep target's JSONB pattern.** It's already in production. Feature rendering in `PlanCard.tsx` already iterates `limits` entries.

4. **2-column layout target files** — Both `/client/billing/BillingPageClient.tsx` and `/dashboard/billing/BillingPageClient.tsx` are identical. The layout change must be applied to **both files** (or extracted to a shared component).

---

## Summary of New Work

| Item | Type | Effort |
|---|---|---|
| `PlanDetailsCard` new component | New component | Small |
| 2-column layout in both `BillingPageClient.tsx` files | Layout edit | Trivial |
| `SubscriptionCard.tsx` visual polish (icon, subtitle) | Edit | Trivial |
| `PaymentHistoryTable.tsx` — per-row provider link + i18n fix | Edit | Trivial |
| `OrderConfirmation.tsx` — add amount + interval | Edit | Trivial |
| `CancelSubscriptionDialog.tsx` — add icon + warning | Edit | Trivial |
