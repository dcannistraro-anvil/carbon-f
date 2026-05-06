# Phase 7: CTA-E (Elimination-Specific CTA)

## Goal

When generating elimination entries, detect FX differences between the two sides of an IC transaction and post the difference to a dedicated CTA-Elimination account. This ensures consolidated statements balance when IC transactions span currencies.

## Current State

- `translateTrialBalance()` calculates CTA per company during currency translation (Phase 2)
- `generateEliminationEntries()` creates reversing entries on elimination entities but assumes amounts match exactly
- When Company A (USD) sells to Company B (EUR), the IC receivable and IC payable are recorded in different currencies
- After translation, these amounts may differ due to rate changes between transaction date and period end
- This difference currently falls through — no CTA-E posting

## Design

### When CTA-E Arises

1. Company A (USD) records IC Receivable of $1,000
2. Company B (EUR) records IC Payable of €920 (at transaction-date rate of 1.087)
3. At period end, closing rate is 1.10 → €920 translates to $1,012
4. Elimination reverses $1,000 receivable and $1,012 payable → $12 difference
5. The $12 posts to CTA-E account on the elimination entity

### Schema Changes

```sql
-- Add CTA-E account to account defaults
-- (This is a new row in accountDefault, not a schema change)
INSERT INTO "accountDefault" ...
-- Key: 'ctaEliminationAccount', default account number: 3210
```

Add `ctaEliminationAccount` to the `accountDefault` configuration (alongside existing `currencyTranslationAccount`).

### Logic Changes in `generateEliminationEntries()`

Current flow:
1. Find matched IC transactions
2. For each pair, create reversing entries on elimination entity
3. Update status to Eliminated

New flow:
1. Find matched IC transactions
2. For each pair:
   a. Get source journal line amount (in source currency)
   b. Get target journal line amount (in target currency)
   c. Translate both to the group's reporting currency using period-end rates
   d. Create reversing entries for the **translated** amounts
   e. If translated source ≠ translated target, post difference to CTA-E
3. Update status to Eliminated

### CTA-E Journal Entry Structure

For the example above ($12 difference):

| Account | Debit | Credit | Company |
|---------|-------|--------|---------|
| IC Receivable (reversal) | | $1,000 | Elimination Entity |
| IC Payable (reversal) | $1,012 | | Elimination Entity |
| CTA-E (3210) | | $12 | Elimination Entity |

### Edge Cases

- **Same currency IC transactions**: No CTA-E needed (amounts will match exactly)
- **Multiple currency pairs in one elimination run**: Each pair calculates its own CTA-E
- **Missing exchange rates**: Use existing fallback logic (closing → 1.0) with a warning

## Files to Modify

| File | Change |
|------|--------|
| Migration | Add `ctaEliminationAccount` to account defaults seed data |
| `generateEliminationEntries()` RPC | Add translated amount comparison and CTA-E posting |
| Elimination report UI | Show CTA-E column/amounts |
| `AccountDefaultsForm` | Add CTA-E account field |
