// credit: Matt Aitken at trigger.dev
import { useLocation, useNavigation } from "react-router";

export function useOptimisticLocation() {
  const navigation = useNavigation();
  const location = useLocation();

  if (navigation.state === "idle" || !navigation.location) {
    return location;
  }

  return navigation.location;
}
