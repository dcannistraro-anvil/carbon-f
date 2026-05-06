import type { LoaderFunctionArgs } from "react-router";
import { redirect } from "react-router";
import { path } from "~/utils/path";

export async function loader({ params }: LoaderFunctionArgs) {
  const { journalEntryId } = params;
  if (!journalEntryId) throw new Error("Could not find journalEntryId");
  throw redirect(path.to.journalEntryDetails(journalEntryId));
}
