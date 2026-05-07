import type { Mode } from "@carbon/utils";
import { modeValidator } from "@carbon/utils";
import { useFetchers } from "react-router";
import { useRouteData } from "./useRouteData";

export function useOptimisticMode() {
  const fetchers = useFetchers();
  const modeFetcher = fetchers.find((f) => f.formAction === "/");

  if (modeFetcher && modeFetcher.formData) {
    const mode = { mode: modeFetcher.formData.get("mode") };
    const submission = modeValidator.safeParse(mode);

    if (submission.success) {
      return submission.data.mode;
    }
  }
}

export function useMode() {
  const optimisticMode = useOptimisticMode();
  const routeData = useRouteData<{ mode: Mode }>("/");

  let mode = routeData?.mode ?? "light";

  if (optimisticMode && optimisticMode !== "system") {
    mode = optimisticMode;
  }

  return mode;
}
