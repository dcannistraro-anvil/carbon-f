import { Edition } from "@carbon/utils";
import { useRouteData } from "./useRouteData";

export function useEdition() {
  const routeData = useRouteData<{ env: { CARBON_EDITION: Edition } }>("/");
  return routeData?.env?.CARBON_EDITION ?? Edition.Community;
}
