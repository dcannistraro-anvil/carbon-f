import { Plan } from "@carbon/utils";

export type PlanRequirement = Plan | Plan[];

export const DEFAULT_ALLOWED_PLANS: Plan[] = [
  Plan.Starter,
  Plan.Business,
  Plan.Partner
];

/**
 * Returns true when the user's current plan satisfies the requirement.
 *
 * `Plan.Unknown` always passes — it represents a loading state, and gating
 * on it would flash upgrade overlays during route transitions.
 */
export function planMeetsRequirement(
  current: Plan,
  plan: PlanRequirement = DEFAULT_ALLOWED_PLANS
): boolean {
  if (current === Plan.Unknown) return true;
  const allowed = Array.isArray(plan) ? plan : [plan];
  if (allowed.length === 0) return true;
  return allowed.includes(current);
}

export function defaultUpgradeMessage(
  plan: PlanRequirement = DEFAULT_ALLOWED_PLANS
): string {
  const allowed = Array.isArray(plan) ? plan : [plan];
  if (allowed.length === 1 && allowed[0] === Plan.Business) {
    return "Upgrade to the Business plan to enable this feature.";
  }
  return "Upgrade your plan to enable this feature.";
}
