import { useMount, useOptimisticLocation, useUrlParams } from "@carbon/react";
import { generateId } from "ai";
import { useCallback } from "react";
import { path } from "~/utils/path";

export function useChatInterface() {
  const [params, setParams] = useUrlParams();
  const location = useOptimisticLocation();
  const chatId = params.get("c") || null;

  const isChatPage = !!chatId;
  const isHome = location.pathname === path.to.authenticatedRoot;

  useMount(() => {
    if (isHome && !chatId) {
      setParams({ c: generateId() });
    }
  });

  const setChatId = useCallback(
    (id: string) => {
      setParams({ c: id });
    },
    [setParams]
  );

  return {
    isChatPage,
    chatId,
    setChatId
  };
}
