import NProgress from "nprogress";
import { useEffect } from "react";
import { useNavigation } from "react-router";

export function useNProgress() {
  const transition = useNavigation();

  useEffect(() => {
    if (
      (transition.state === "loading" || transition.state === "submitting") &&
      !NProgress.isStarted()
    ) {
      NProgress.start();
    } else {
      NProgress.done();
    }
  }, [transition.state]);
}
