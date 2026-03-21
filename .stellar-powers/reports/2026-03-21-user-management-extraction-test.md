# User Management Feature Extraction Report

**Date:** 2026-03-21
**Source project:** /Volumes/Ext-nvme/Development/subsheroload (SubsHero)
**Target project:** /Users/rohits/dev/stellar-powers (Stellar Powers)
**Feature scope:** User CRUD, profile, roles/permissions (excluding billing, subscriptions, team management)

---

## Source Stack Summary

- **Backend:** Laravel 12 (PHP 8.3+) with Inertia.js adapter
- **Frontend:** React 19 + TypeScript + Vite, Inertia.js (server-driven SPA)
- **Database:** MySQL (relational)
- **Key libraries:** Spatie Laravel Permission (roles/permissions), Laravel Orion (REST resource layer), Laravel Sanctum (API tokens), Spatie Google Calendar, OpenAI PHP client
- **Auth:** Dual-guard — `web` guard for regular users, `admin` guard for admin users
- **Communication pattern:** Inertia.js (HTML responses for page loads) + JSON API (AJAX calls within pages, admin API under `/admin/api/`)
- **Styling:** Tailwind CSS v4 + shadcn/ui components

---

## Target Stack Summary

- **Type:** Claude Code plugin (not a web app)
- **Runtime:** Node.js (JavaScript/TypeScript), no server
- **Backend:** None — plugin runs inside Claude Code CLI process
- **Frontend:** None — CLI/markdown output only
- **Database:** None — uses flat files (`.stellar-powers/workflow.jsonl`, SKILL.md files)
- **Key libraries:** None (zero-dependency design)
- **Communication pattern:** Claude Code skill/agent invocation system
- **Overlap with source:** Minimal by design — source is a SaaS web application, target is a CLI plugin

---

## Backend Analysis

### Routes / API Endpoints

#### End-User Profile Routes (web guard, `/profile`)

| Method | URL | Handler | Middleware |
|---|---|---|---|
| GET | `/profile` | `ProfileController@edit` | `auth`, `verified`, `prevent.admin.regular`, `require.onboarding` |
| PATCH | `/profile` | `ProfileController@update` | same group |
| DELETE | `/profile` | `ProfileController@destroy` | same group |
| GET | `/profile/countries` | `ProfileController@getCountries` | same group |
| GET | `/profile/timezones` | `ProfileController@getTimezones` | same group |
| GET | `/profile-photos/{userId}/{filename}` | `ProfilePhotoController@show` | `auth:web,admin` |

#### Admin — End-User CRUD (Orion REST resource, `/api/admin/users`)

Exposes standard Orion resource routes: `GET /api/admin/users` (index), `POST` (store), `GET /{user}` (show), `PUT /{user}` (update), `DELETE /{user}` (destroy), plus:

| Method | URL | Handler | Middleware |
|---|---|---|---|
| POST | `/api/admin/users/{user}/send-verification-email` | `UserController@sendVerificationEmail` | `admin.auth` |
| POST | `/api/admin/users/{user}/toggle-email-verification` | `UserController@toggleEmailVerification` | `admin.auth` |

#### Admin — Admin User CRUD (`/admin/api/admin-users`)

| Method | URL | Handler | Middleware |
|---|---|---|---|
| GET | `/admin/api/admin-users` | `AdminUserController@index` | `permission:admins.view,admin` |
| GET | `/admin/api/admin-users/{adminUser}` | `AdminUserController@show` | `permission:admins.view,admin` |
| POST | `/admin/api/admin-users` | `AdminUserController@store` | `permission:admins.create,admin` |
| PUT | `/admin/api/admin-users/{adminUser}` | `AdminUserController@update` | `permission:admins.update,admin` |
| DELETE | `/admin/api/admin-users/{adminUser}` | `AdminUserController@destroy` | `permission:admins.delete,admin` |
| POST | `/admin/api/admin-users/{adminUser}/roles` | `AdminUserController@assignRoles` | `permission:admins.assign_roles,admin` |

#### Admin — Roles & Permissions (`/admin/api/roles`)

| Method | URL | Handler | Middleware |
|---|---|---|---|
| GET | `/admin/api/roles` | `RoleController@index` | `permission:admins.view,admin` |
| GET | `/admin/api/roles/{name}` | `RoleController@show` | `permission:admins.view,admin` |
| GET | `/admin/api/roles/permissions/all` | `RoleController@permissions` | `permission:admins.view,admin` |

#### Admin — Impersonation (`/api/admin/impersonation`)

| Method | URL | Handler | Middleware |
|---|---|---|---|
| POST | `/api/admin/impersonation/users/{userId}/start` | `ImpersonationController@start` | `admin.auth` |
| GET | `/api/admin/impersonation/logs` | `ImpersonationController@logs` | `admin.auth` |
| GET | `/api/admin/impersonation/logs/export` | `ImpersonationController@export` | `admin.auth` |
| GET | `/api/admin/impersonation/statistics` | `ImpersonationController@statistics` | `admin.auth` |
| GET | `/api/admin/impersonation/users/{userId}/can-impersonate` | `ImpersonationController@canImpersonate` | `admin.auth` |

---

### Controllers / Handlers

#### `ProfileController` (Settings\ProfileController)

- `edit()` — Renders Inertia page `app/settings/profile`, passes `mustVerifyEmail`, `status`
- `update(ProfileUpdateRequest)` — Handles profile photo upload (private local storage, user-specific folder), fills user with validated data, resets `email_verified_at` if email changed, responds to both Inertia and AJAX
- `getCountries()` — Returns all countries (id, name, iso, emoji)
- `getTimezones(Request)` — Returns timezones filtered by `country_id`
- `destroy(Request)` — Validates `current_password`, deletes profile photo, logs out, deletes user, invalidates session

#### `UserController` (Api\Admin\UserController — Orion)

Extends Orion `StandardOrionController`. Key behaviors:
- `searchableBy()` — name, first_name, last_name, email, phone, company_name
- `filterableBy` — id, name, email, email_verified_at, phone, company_name, user_type, timezone, country_id, status, timestamps
- `sortableBy` — standard fields plus `subscriptions_count`
- `alwaysIncludes` — settings, country, userPlan
- `runIndexFetchQuery()` — custom: eager-loads userPlan with GlobalScope bypassed, adds subscription count, custom filters for status (active/inactive string mapping), plan_type, email_verified_at
- `sendVerificationEmail()` — sends verification email to user
- `toggleEmailVerification()` — manually sets or clears `email_verified_at`

#### `AdminUserController` (Api\Admin\AdminUserController)

- `index(Request)` — Lists AdminUsers with roles; search by name/email; filter by role; sort by id/name/email/timestamps; paginates (max 100/page)
- `show(AdminUser)` — Returns single admin user with roles and all permissions
- `store(Request)` — Validates name, email (unique:admin_users), password (Password::defaults()), roles (array, min:1, exists:roles,name). Creates user, assigns roles filtered to `guard_name=admin`, logs activity. Wraps in DB transaction.
- `update(Request, AdminUser)` — Validates optionally. Guards: cannot remove own super_admin role; last-super_admin protection. Updates fields, syncs roles, logs role change, invalidates other user's sessions on role change. DB transaction.
- `destroy(AdminUser)` — Guards: self-protection; last-super_admin protection. Logs before delete, invalidates sessions, deletes.
- `assignRoles(Request, AdminUser)` — Same guards as update. Syncs roles, logs, invalidates sessions.
- Private `invalidateUserSessions(AdminUser)` — Deletes from `sessions` table where `user_id` matches (only for database session driver).

#### `RoleController` (Api\Admin\RoleController)

- `index()` — Lists all admin-guard roles with permissions, permissions_count, users_count, display_name, description
- `show(string $name)` — Single role with permissions grouped by resource
- `permissions()` — All permissions for admin guard, flat list + grouped by resource (format: `resource.action`)
- Roles are predefined (no create/edit/delete in v1). Custom management planned for v2.

#### `ImpersonationController`

- `start(Request, int $userId)` — Validates `reason` (min:10, max:500). Checks user exists and allows impersonation. Delegates to `ImpersonationService`. Returns redirect_url and session expiry.
- `logs(Request)` — Paginated logs with search + filters (admin_user_id, impersonated_user_id, status, date range)
- `export(Request)` — CSV export with same filters
- `statistics(Request)` — Aggregate counts (total, active, completed, expired, terminated sessions, average duration)
- `canImpersonate(Request, int $userId)` — Checks if admin can impersonate given user

---

### Models / Schema

#### `users` table (regular users)

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| name | string(255) | Derived from first_name + last_name if empty |
| first_name | string(255) nullable | |
| last_name | string(255) nullable | |
| email | string(255) unique | lowercase |
| email_verified_at | timestamp nullable | |
| password | string hashed | |
| remember_token | string(100) nullable | |
| phone | string(255) nullable | |
| company_name | string(255) nullable | |
| description | string(1000) nullable | |
| user_type | integer | 1=ADMIN, 2=REGULAR, 3=TEAMS |
| profile_photo_path | string nullable | Stored in private local storage |
| timezone | string(255) nullable | |
| country_id | integer FK nullable | → countries.id |
| status | integer | active/inactive |
| onboarding_completed | boolean | |
| completed_tours | json array | |
| allow_admin_impersonation | boolean | |
| ai_credits_allocated | integer | |
| ai_credits_used | integer | |
| ai_credits_reset_at | timestamp nullable | |
| sub_ltd | (type TBD) nullable | Lifetime deal flag |
| is_demo | boolean | |
| google_access_token | string nullable | |
| google_refresh_token | string nullable | |
| google_token_expires_at | timestamp nullable | |
| google_calendar_id | string nullable | |
| google_calendar_connected_at | timestamp nullable | |
| created_at, updated_at | timestamps | |

Key relationships: hasOne UserSetting, belongsTo Country, hasMany subscriptions/transactions/folders/paymentMethods/contacts/reminders/plans, hasOne userPlan (with GlobalScope bypass needed for admin), hasOneThrough shopPlan.

#### `admin_users` table

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| name | string(255) | |
| email | string(255) unique | |
| password | string hashed | |
| remember_token | string(100) nullable | |
| email_verified_at | timestamp nullable | |
| created_at, updated_at | timestamps | |

Uses Spatie HasRoles trait with `guard_name = 'admin'`.

#### Spatie Permission tables

Standard Spatie Laravel Permission schema: `permissions` (id, name, guard_name), `roles` (id, name, guard_name), `model_has_permissions`, `model_has_roles`, `role_has_permissions`. Scoped to guard_name to separate web/admin guards.

---

### Roles and Permissions

Six predefined roles (all `guard_name = 'admin'`):

| Role | Permissions |
|---|---|
| super_admin | All permissions (also bypassed via Gate::before) |
| content_manager | products.*, categories.*, platforms.*, product_types.* |
| user_manager | users.view/create/update/delete/impersonate, admins.view |
| sales_manager | orders.view/update/refund, coupons.*, users.view |
| marketing_manager | email_templates.*, social_media.*, coupons.* |
| viewer | *.view for all resources |

Permission format: `resource.action` (e.g. `users.impersonate`, `admins.assign_roles`).

---

### Middleware

- `admin.auth` — Verifies admin guard authentication
- `admin.guest` — Redirects authenticated admins away from login pages
- `prevent.admin.regular` — Prevents admin users from accessing regular user pages
- `require.onboarding` — Redirects if `onboarding_completed = false`
- `permission:{permission},{guard}` — Spatie permission middleware, used on all admin-user CRUD routes

---

### Business Logic / Security Rules

**Self-protection (AdminUserController):**
1. Cannot delete your own admin account (403)
2. Cannot remove your own `super_admin` role (403)
3. Cannot delete the last super_admin (403)
4. Cannot remove super_admin role from the only remaining super_admin (403)

**Session invalidation:** When an admin user's roles are changed by another admin, all their active sessions are deleted from the `sessions` table (database session driver only).

**Impersonation rules:**
- Requires `reason` with minimum 10 characters
- User must have `allow_admin_impersonation = true`
- Admin must have `users.impersonate` permission
- Sessions expire (TTL set in ImpersonationService)
- All impersonation sessions are logged with admin_user_id, impersonated_user_id, reason, started_at, ended_at, duration, actions_count, status, ip_address

**Profile photo:** Stored in private storage (`local` disk) in user-specific subfolder (`profile-photos/user-{id}/`). Served via authenticated route. Old photo deleted on update.

**Email change:** Clears `email_verified_at` when email is updated.

---

### Validation Rules

#### Profile Update (ProfileUpdateRequest)

- `name` — required string max:255 (sometimes if photo-only upload)
- `first_name` — nullable string max:255
- `last_name` — nullable string max:255
- `email` — required lowercase email max:255, unique ignoring own id
- `phone` — nullable string max:255
- `company_name` — nullable string max:255
- `description` — nullable string max:1000
- `country_id` — nullable integer exists:countries
- `timezone` — nullable string max:255
- `profile_photo` — nullable image (jpeg/png/jpg/gif) max:2048KB

#### Admin User Create (AdminUserController@store)

- `name` — required string max:255
- `email` — required email max:255 unique:admin_users
- `password` — required Password::defaults()
- `roles` — required array min:1, each must exist in roles table

#### Admin User Update (AdminUserController@update)

- Same as create but all fields `sometimes`
- Password is nullable (skip hash if empty)

#### Account Delete (ProfileController@destroy)

- `password` — required, validated as current_password

---

### Background Jobs / Events

- `AdminActivityLog::logAdminCreated()` — records admin creation with roles
- `AdminActivityLog::logAdminUpdated()` — records old/new field values
- `AdminActivityLog::logAdminDeleted()` — records deletion before it happens
- `AdminActivityLog::logRoleAssignment()` — records old_roles → new_roles diff
- All logging is synchronous (no queue jobs for this feature)
- Email verification is sent via `sendVerificationEmail()` (triggers Laravel's built-in verification email)

---

## Frontend Analysis

### Pages / Views

| Route | Component | Purpose |
|---|---|---|
| `/admin/users` | `Admin/users.tsx` | Admin manages regular end-users (uses UsersTable + UserFormDialog) |
| `/admin/admin-users` | `Admin/admin-users.tsx` | Admin manages other admin accounts (uses AdminUsersTable + AdminUserFormDialog) |
| `/admin/roles` | `Admin/roles.tsx` | Read-only view of roles with permission breakdown |
| `/profile` | `app/settings/profile.tsx` | Authenticated user edits own profile |

### Components

- `components/admin/users-table.tsx` — Data table for end-users; handles search, filter (status, plan_type, verified), sort, pagination; calls `/api/admin/users`
- `components/admin/user-form-dialog.tsx` — Create/edit end-user modal; renders based on `can('users.create')` permission check
- `components/admin/admin-users-table.tsx` — Data table for admin users; calls `/admin/api/admin-users`
- `components/admin/admin-user-form-dialog.tsx` — Create/edit admin user modal; includes role assignment; `can('admins.create')` gated
- `components/admin/role-badge.tsx` — Pill badge for role display
- `components/app/delete-user.tsx` — User self-deletion component (requires password confirmation)
- `hooks/use-admin-permission.ts` — `can(permission)` helper consumed by pages and components
- `hooks/use-admin-users.ts` — State hook: fetches roles list, exposes `createAdminUser()` action

### API Integration (Frontend)

- Admin user table: `fetch('/admin/api/admin-users', { credentials: 'same-origin' })`
- Roles page: parallel `fetch('/admin/api/roles')` + `fetch('/admin/api/roles/permissions/all')`
- End-user table: Orion-compatible query params (`search=`, `filter[status]=`, `sort=-created_at`, `include=userPlan,country`)
- Profile form: Inertia `useForm` + `patch(route('profile.update'))` — full Inertia form submission
- Photo upload: separate request via `multipart/form-data` (photo-only detection logic in backend request class)

### Styling Patterns

- Tailwind CSS + shadcn/ui: Card, Button, Badge, Dialog, Table, Input, Label, Collapsible
- Admin layout wraps all admin pages with `AdminLayout` component
- `SidebarProvider` + `SidebarApp` (inset variant) + `SiteHeader` in every admin page
- Container class: `admin-container` with `flex flex-col gap-4 py-4 md:gap-6 md:py-6`
- Permission-gated "Add" buttons: `{can('resource.create') && <Button>...}</Button>}`

---

## Phase 3: Target Overlap Scan

Stellar Powers is a Claude Code plugin. It has:
- No HTTP routes, no database, no user accounts
- No concept of "admin users" or "regular users"
- No profile system
- No roles or permissions (Claude Code handles auth externally)
- The only "users" concept is Claude Code sessions, which is not managed by the plugin

**Conclusion:** Zero meaningful overlap. The source feature is entirely web-application-specific infrastructure.

---

## Phase 4: Mapping Table

| Source Item | Target Status | Notes |
|---|---|---|
| `users` table schema | Skip | Target has no database |
| `admin_users` table schema | Skip | Target has no admin panel |
| Spatie Permission tables | Skip | No permission system in CLI plugin |
| `ProfileController` | Skip | No user profiles in target |
| `AdminUserController` | Skip | No admin panel |
| `RoleController` | Skip | No role management |
| `ImpersonationController` | Skip | No user sessions to impersonate |
| `ProfileUpdateRequest` validation | Skip | No form validation layer |
| Admin roles seeder (6 roles) | Skip | No database |
| `AdminActivityLog` model | Skip | No audit log infrastructure |
| `users.tsx` (end-user management page) | Skip | No web UI |
| `admin-users.tsx` (admin management page) | Skip | No web UI |
| `roles.tsx` (roles viewer page) | Skip | No web UI |
| `app/settings/profile.tsx` | Skip | No web UI |
| `use-admin-permission` hook | Skip | No permission system |
| `use-admin-users` hook | Skip | No API layer |
| `UserFormDialog` component | Skip | No web UI |
| `AdminUserFormDialog` component | Skip | No web UI |
| Self-protection business rules | Skip | Not applicable |
| Session invalidation on role change | Skip | Not applicable |
| Impersonation audit trail | Skip | Not applicable |
| Profile photo upload/storage | Skip | Not applicable |

---

## New Work Required

**None.** This feature has no applicable port target. Stellar Powers is a Claude Code plugin with fundamentally different architecture — no server, no database, no user accounts, no web UI. All 20 scanned items are categorized as Skip.

---

## Exists But Needs Update

**None.**

---

## Can Skip

All 20 items in the mapping table are Skip. The source feature is a complete web-application user management system (dual-guard auth, RBAC via Spatie, Inertia/React UI). The target is a zero-dependency CLI plugin. The architectural gap is total.

---

## Shared Dependencies

**None identified.** No source dependencies (Spatie Permission, Laravel Orion, Sanctum, Inertia) exist in the target stack.

---

## Environment Variables

Variables used by this feature in the source project:

| Variable | Purpose | Required |
|---|---|---|
| `SESSION_DRIVER` | Determines if session invalidation (DB delete) applies | Required |
| `SESSION_LIFETIME` | Session expiry duration | Required |
| `APP_URL` | Used in verification emails | Required |
| `FILESYSTEM_DISK` | Disk for profile photo storage (`local` used) | Optional (defaults) |

No environment variables are applicable to the target project.

---

## Test Coverage (Source — Reference Only, Not Ported)

Scenarios covered in source `tests/` (Pest):
- Profile update with valid data → 200 with updated fields
- Profile update clears `email_verified_at` when email changes
- Profile update rejects duplicate email
- Photo upload — accepts jpeg/png, rejects non-image
- Password validation on account delete
- Admin create with valid roles → 201
- Admin create with invalid role name → 422
- Admin delete self → 403
- Admin delete last super_admin → 403
- Role assignment removes own super_admin → 403
- Impersonation requires `allow_admin_impersonation = true`
- Impersonation reason minimum length enforced
- Log export produces valid CSV

These inform what edge cases are important for any future user management feature in the target, should the target ever evolve toward a server-based architecture.

---

## Incomplete

This report covers the full defined scope. The following areas were intentionally excluded per the user context constraint:
- Billing/subscription management (UserPlan, ShopPlan, SubsSubscription)
- Team management (UserTeam)
- AI credit system (AiCreditTransaction, AiUsageTracking)
- Marketplace user features
