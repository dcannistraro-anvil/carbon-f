# UI Testing Plan: Company Group Refactoring + Dimensions Feature

## Context
Two major changes are staged:
1. **Company Group Refactoring** - Accounting entities (accounts, categories, currencies, dimensions) now scope to `companyGroupId` instead of `companyId`. This affects auth sessions, the service layer, and ~30 route files.
2. **Dimensions Feature** - New accounting dimensions UI (list, create, edit, delete) built in prior commits. The staged changes wire it to `companyGroupId`.

The risk is that any broken `companyGroupId` lookup will cause pages to fail to load or data to silently filter incorrectly. Every affected UI area must be visited to verify data loads and mutations work.

---

## Pre-Requisites
- [ ] Database migration `20260224024512_dimensions.sql` has been applied
- [ ] Dev server is running (`npm run dev` or equivalent)
- [ ] Logged in as a user with full accounting permissions
- [ ] At least one company exists with a valid `companyGroupId`

---

## Test 1: Authentication & Session (Critical Path)

These changes touch the auth session — if broken, nothing else works.

| # | Step | Expected Result |
|---|------|-----------------|
| 1.1 | Log out and log back in | Login succeeds, redirected to dashboard |
| 1.2 | Open browser devtools > Application > Cookies/Session | Session contains `companyGroupId` field |
| 1.3 | Navigate to any accounting page | Page loads without 500 error |
| 1.4 | Let session idle until token refresh triggers | App continues working after refresh (no logout) |

**Files:** `packages/auth/src/services/auth.server.ts`, `packages/auth/src/services/session.server.ts`, `packages/auth/src/types.ts`

---

## Test 2: Company Switching

| # | Step | Expected Result |
|---|------|-----------------|
| 2.1 | Go to Settings > Company, switch to a different company | Redirected to dashboard, new company context active |
| 2.2 | Navigate to Accounting > Chart of Accounts | Data loads for the switched company's group |
| 2.3 | Switch back to original company | Data reverts to original company group's data |

**Files:** `apps/erp/app/routes/x+/settings+/company.switch.$companyId.tsx`, `apps/erp/app/routes/x+/_layout.tsx`

---

## Test 3: Onboarding & Invite Flows

| # | Step | Expected Result |
|---|------|-----------------|
| 3.1 | Create a new company via onboarding flow | Company created, session updated with companyGroupId, redirected correctly |
| 3.2 | Accept an invite to a company (if testable) | Session updated with new companyId + companyGroupId |

**Files:** `apps/erp/app/routes/onboarding+/company.tsx`, `apps/erp/app/routes/_public+/invite.$code.tsx`

---

## Test 4: Chart of Accounts (`/x/accounting/charts`)

| # | Step | Expected Result |
|---|------|-----------------|
| 4.1 | Navigate to Accounting > Chart of Accounts | Account list loads with data |
| 4.2 | Filter by Income Statement / Balance Sheet | Filters work correctly |
| 4.3 | Search for an account by name | Search returns matching results |
| 4.4 | Click "New Account" | Form drawer opens |
| 4.5 | Fill in form and submit | Account created successfully, appears in list |

**Files:** `apps/erp/app/routes/x+/accounting+/charts.tsx`, `apps/erp/app/routes/x+/accounting+/charts.new.tsx`

---

## Test 5: Account Categories (`/x/accounting/categories`)

| # | Step | Expected Result |
|---|------|-----------------|
| 5.1 | Navigate to Accounting > Categories | Category list loads |
| 5.2 | Search for a category | Search returns results |
| 5.3 | Click "New Category" | Form opens |
| 5.4 | Fill in and submit | Category created, appears in list |
| 5.5 | Click an existing category | Detail/edit view loads with subcategories |

**Files:** `apps/erp/app/routes/x+/accounting+/categories.tsx`, `apps/erp/app/routes/x+/accounting+/categories.new.tsx`, `apps/erp/app/routes/x+/accounting+/categories.$categoryId.tsx`, `apps/erp/app/routes/x+/accounting+/categories.list.$categoryId.tsx`

---

## Test 6: Currencies (`/x/accounting/currencies`)

| # | Step | Expected Result |
|---|------|-----------------|
| 6.1 | Navigate to Accounting > Currencies | Currency list loads |
| 6.2 | Search for a currency | Search works |
| 6.3 | Click a currency | Detail view loads with exchange rate |
| 6.4 | Verify base currency shows in accounting layout | Base currency indicator is correct |

**Files:** `apps/erp/app/routes/x+/accounting+/currencies.tsx`, `apps/erp/app/routes/x+/accounting+/currencies.$currencyId.tsx`

---

## Test 7: Dimensions (`/x/accounting/dimensions`) — New Feature

| # | Step | Expected Result |
|---|------|-----------------|
| 7.1 | Navigate to Accounting > Dimensions | Empty table or list of dimensions loads |
| 7.2 | Click "New Dimension" | Drawer form opens |
| 7.3 | Create a Custom dimension with name + values | Dimension created, appears in list with correct value count |
| 7.4 | Create a Location dimension | Dimension created (no custom values field shown) |
| 7.5 | Create dimensions for each entity type: ItemPostingGroup, SupplierType, CustomerType, Department, Employee | Each creates successfully |
| 7.6 | Click an existing Custom dimension | Edit form opens with pre-populated values, entity type is read-only |
| 7.7 | Add a new value to a Custom dimension | Value saved, count updates |
| 7.8 | Remove a value from a Custom dimension | Value removed on save |
| 7.9 | Toggle "Required" checkbox on a dimension | Saves correctly |
| 7.10 | Toggle "Active" checkbox off | Dimension hidden from active list |
| 7.11 | Delete a dimension via context menu | Confirmation modal appears, dimension removed after confirm |
| 7.12 | Verify entity type filter in table | Filtering by entity type works |

**Files:** `apps/erp/app/routes/x+/accounting+/dimensions.tsx`, `apps/erp/app/routes/x+/accounting+/dimensions.new.tsx`, `apps/erp/app/routes/x+/accounting+/dimensions.$dimensionId.tsx`, `apps/erp/app/routes/x+/accounting+/dimensions.delete.$dimensionId.tsx`

---

## Test 8: Exchange Rates (Cross-Module)

These routes fetch currency by code using `companyGroupId` now.

| # | Step | Expected Result |
|---|------|-----------------|
| 8.1 | Open a Purchase Invoice with a non-base currency | Exchange rate loads correctly |
| 8.2 | Open a Purchase Order with a non-base currency | Exchange rate loads correctly |
| 8.3 | Open a Sales Invoice with a non-base currency | Exchange rate loads correctly |
| 8.4 | Open a Sales Order with a non-base currency | Exchange rate loads correctly |
| 8.5 | Open a Quote with a non-base currency | Exchange rate loads correctly |
| 8.6 | Open a Supplier Quote | Loads correctly with presentation currency |

**Files:** `apps/erp/app/routes/x+/purchase-invoice+/$invoiceId.exchange-rate.tsx`, `apps/erp/app/routes/x+/purchase-order+/$orderId.exchange-rate.tsx`, `apps/erp/app/routes/x+/sales-invoice+/$invoiceId.exchange-rate.tsx`, `apps/erp/app/routes/x+/sales-order+/$orderId.exchange-rate.tsx`, `apps/erp/app/routes/x+/quote+/$quoteId.exchange-rate.tsx`, `apps/erp/app/routes/x+/supplier-quote+/$id.tsx`, `apps/erp/app/routes/x+/supplier-quote+/$id.exchange-rate.tsx`

---

## Test 9: Inventory & Items (Cross-Module)

These routes now pass `companyGroupId` to `getAccountsList`.

| # | Step | Expected Result |
|---|------|-----------------|
| 9.1 | Navigate to Inventory > Shipping Methods | Page loads, account dropdowns populated |
| 9.2 | Navigate to Items > Groups | Page loads, account dropdowns populated |

**Files:** `apps/erp/app/routes/x+/inventory+/shipping-methods.tsx`, `apps/erp/app/routes/x+/items+/groups.tsx`

---

## Test 10: MES & Starter App Company Switching

| # | Step | Expected Result |
|---|------|-----------------|
| 10.1 | In MES app, switch companies | Company switch works, session updated |
| 10.2 | In Starter app, switch companies | Company switch works, session updated |

**Files:** `apps/mes/app/routes/x+/company.switch.$companyId.tsx`, `apps/starter/app/routes/x+/company.switch.$companyId.tsx`

---

## Test 11: Edge Functions (Backend Verification)

| # | Step | Expected Result |
|---|------|-----------------|
| 11.1 | Trigger a company seed (if applicable) | Seed function completes without errors |
| 11.2 | Create a document that triggers the `create` edge function | Edge function handles `companyGroupId` correctly |
| 11.3 | Post a purchase invoice | Journal entries created with correct company context |

**Files:** `packages/database/supabase/functions/seed-company/index.ts`, `packages/database/supabase/functions/create/index.ts`, `packages/database/supabase/functions/post-purchase-invoice/index.ts`, `packages/database/supabase/functions/lib/api/accounting.ts`

---

## Priority Order
1. **Test 1** (Auth/Session) — if this fails, everything fails
2. **Test 2** (Company Switching) — core navigation
3. **Test 4-6** (Chart of Accounts, Categories, Currencies) — bread-and-butter accounting
4. **Test 7** (Dimensions) — new feature validation
5. **Test 8-9** (Exchange Rates, Inventory/Items) — cross-module regression
6. **Test 3, 10-11** (Onboarding, MES/Starter, Edge Functions) — lower frequency flows
