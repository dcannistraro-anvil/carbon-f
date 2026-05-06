import type { SupabaseClient } from "@supabase/supabase-js";

const INTERNAL_EMAIL_DOMAINS = ["@carbon.us.org", "@carbon.ms"];

export async function isInternalUser(
  client: SupabaseClient,
  userId: string
): Promise<boolean> {
  const { data } = await client.auth.admin.getUserById(userId);
  if (!data?.user?.email) return false;
  return INTERNAL_EMAIL_DOMAINS.some((domain) =>
    data.user.email!.includes(domain)
  );
}
