# Refactor: Configurable Upgrade Overlay System

## Context

3 near-duplicate overlay components exist (ApiKeysUpgradeOverlay,
WebhooksUpgradeOverlay, AuditLogUpgradeOverlay) plus an inline
upgrade-restricted block inside `AuditLogDrawer.tsx`. Server gate is
`requireBusinessPlan` (currently buggy: `return true;` short-circuits all
logic). `audit-logs.tsx` action duplicates the gate inline. Client-side
gate pattern `isCloud && plan === Plan.Starter` is repeated across 6+
files.

Goal: shared, composable upgrade-overlay system + generic plan-gate
hook + generic server-side `requirePlan`.

## Design (compound components, avoid boolean props)

### `UpgradeOverlay` — compound component

```tsx
<UpgradeOverlay>
  <UpgradeOverlay.Preview>
    <ApiKeysTable data={mockApiKeys} count={mockApiKeys.length} />
  </UpgradeOverlay.Preview>
  <UpgradeOverlay.Card>
    <UpgradeOverlay.Icon><LuKeyRound /></UpgradeOverlay.Icon>
    <UpgradeOverlay.Title>API Keys</UpgradeOverlay.Title>
    <UpgradeOverlay.Description>...</UpgradeOverlay.Description>
    <UpgradeOverlay.Actions>
      <UpgradeOverlay.UpgradeButton />
    </UpgradeOverlay.Actions>
  </UpgradeOverlay.Card>
</UpgradeOverlay>
```

Inline variant for non-overlay contexts (e.g. drawer panel — no preview,
no absolute positioning, no card chrome):

```tsx
<UpgradeOverlay.Inline>
  <UpgradeOverlay.Icon>...</UpgradeOverlay.Icon>
  <UpgradeOverlay.Title>...</UpgradeOverlay.Title>
  <UpgradeOverlay.Description>...</UpgradeOverlay.Description>
  <UpgradeOverlay.Actions>...</UpgradeOverlay.Actions>
</UpgradeOverlay.Inline>
```

Layout pieces (`UpgradeOverlay`, `Preview`, `Card`, `Inline`) provide
positioning. Content pieces (`Icon`, `Title`, `Description`, `Actions`,
`UpgradeButton`) are reusable across both layouts. No boolean variant
props — composition decides shape.

### `usePlanGate` hook

```tsx
const { isGated } = usePlanGate({ requiredPlan: Plan.Business });
if (isGated) return <UpgradeOverlay>...</UpgradeOverlay>;
```

Default `requiredPlan = Plan.Business`. Internally uses `usePlan()` +
`useFlags()`. Returns `{ isGated, plan, requiredPlan }`.

### Server `requirePlan`

```ts
await requirePlan({
  request,
  client,
  companyId,
  redirectTo: path.to.auditLog,
  requiredPlan: Plan.Business,
  message: "Upgrade to enable audit logging",
});
```

Replaces `requireBusinessPlan`. Adds `Edition.Cloud` check (currently
missing — non-cloud installs should never gate). Removes the `return
true;` bug.

## Files

### New

- [ ] `apps/erp/app/components/UpgradeOverlay/UpgradeOverlay.tsx`
- [ ] `apps/erp/app/components/UpgradeOverlay/index.ts`
- [ ] `apps/erp/app/hooks/usePlanGate.ts`
- [ ] `apps/erp/app/utils/planGate.ts` — shared `planMeetsRequirement`

### Modify

- [ ] `apps/erp/app/utils/planGate.server.ts` — replace
      `requireBusinessPlan` with generic `requirePlan`. Add Cloud check.
      Remove dead code.
- [ ] `apps/erp/app/modules/settings/ui/ApiKeys/ApiKeysUpgradeOverlay.tsx`
      — re-implement as composition over `<UpgradeOverlay>`.
- [ ] `apps/erp/app/modules/settings/ui/Webhooks/WebhooksUpgradeOverlay.tsx`
- [ ] `apps/erp/app/modules/settings/ui/AuditLog/AuditLogUpgradeOverlay.tsx`
- [ ] `apps/erp/app/components/AuditLog/AuditLogDrawer.tsx` — replace
      inline `planRestricted` block with `<UpgradeOverlay.Inline>`.
- [ ] Routes calling `requireBusinessPlan` — change to `requirePlan`:
  - `api-keys.$id.tsx`, `api-keys.delete.$id.tsx`, `api-keys.new.tsx`
  - `webhooks.$id.tsx`, `webhooks.delete.$id.tsx`, `webhooks.new.tsx`
  - `integrations.$id.tsx`, `integrations.deactivate.$id.tsx`
- [ ] `audit-logs.tsx` — replace inline action plan check with
      `requirePlan`. Replace `isStarterTeaser` with `usePlanGate`.
- [ ] `api-keys.tsx`, `webhooks.tsx` — fix `if (true)` bug → use
      `usePlanGate` and check `isGated`.
- [ ] `useAuditLog.tsx`, `IntegrationCard.tsx` — replace ad-hoc
      `isCloud && plan === Plan.Starter` with `usePlanGate`.

## Verification

- `npm run typecheck` passes.
- `npm run lingui:compile` passes.
- Spot-check routes (api-keys, webhooks, audit-logs) on Starter +
  Business cloud users.

## Review

(filled in after implementation)
