import { usePlan } from "@carbon/remix";
import { useFlags } from "~/hooks/useFlags";
import {
  DEFAULT_ALLOWED_PLANS,
  type PlanRequirement,
  planMeetsRequirement
} from "~/utils/planGate";

type UsePlanGateOptions = {
  plan?: PlanRequirement;
};

export function usePlanGate({
  plan = DEFAULT_ALLOWED_PLANS
}: UsePlanGateOptions = {}) {
  const currentPlan = usePlan();
  const { isCloud } = useFlags();

  const isGated = isCloud && !planMeetsRequirement(currentPlan, plan);

  return { isGated, plan: currentPlan, allowedPlans: plan };
}
