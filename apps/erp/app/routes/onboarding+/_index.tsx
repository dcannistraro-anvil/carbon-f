import { redirect } from "react-router";
import { onboardingSequence } from "~/utils/path";

export async function loader() {
  throw redirect(onboardingSequence[0]);
}
