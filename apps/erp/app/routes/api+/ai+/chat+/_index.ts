import { requirePermissions } from "@carbon/auth/auth.server";
import { smoothStream } from "ai";
import type { ActionFunctionArgs } from "react-router";
import { orchestrationAgent } from "./agents/orchestration-agent";
import { createChatContext } from "./agents/shared/context";

export async function action({ request }: ActionFunctionArgs) {
  const { client, userId, companyId, companyGroupId } =
    await requirePermissions(request, {});

  const payload = await request.json();

  const {
    message,
    id,
    timezone,
    locale,
    agentChoice,
    toolChoice,
    country,
    city,
    fullName,
    companyName,
    baseCurrency
  } = payload;

  const context = createChatContext({
    userId,
    companyId,
    companyGroupId,
    client,
    fullName,
    companyName,
    country,
    city,
    chatId: id,
    timezone,
    locale,
    baseCurrency
  });

  return orchestrationAgent.toUIMessageStream({
    message,
    context,
    agentChoice,
    toolChoice,
    strategy: "auto",
    maxRounds: 5,
    maxSteps: 20,
    experimental_transform: smoothStream({
      chunking: "word"
    }),
    sendSources: true
  });
}
