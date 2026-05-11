import { normalizePlanId, type Plan } from "@carbon/utils";
import { useRouteData } from "./useRouteData";

export function usePlan(): Plan {
  const routeData = useRouteData<{ plan?: string | null }>("/x");
  return normalizePlanId(routeData?.plan);
}
