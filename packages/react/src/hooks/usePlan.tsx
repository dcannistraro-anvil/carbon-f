import { Plan } from "@carbon/utils";
import { useRouteData } from "./useRouteData";

export function usePlan() {
  const routeData = useRouteData<{ plan?: Plan }>("/x");
  return routeData?.plan ?? Plan.Unknown;
}
