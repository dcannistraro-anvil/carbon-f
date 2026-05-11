import { createHmac, randomBytes } from "node:crypto";

export type JwtCreds = {
  secret: string;
  anonKey: string;
  serviceKey: string;
};

/**
 * Mint a fresh JWT_SECRET + the matching `anon` and `service_role` HS256 JWTs.
 * Mirrors supabase's well-known dev token shape so all downstream services
 * (gotrue, postgrest, kong, storage, studio) accept them without further config.
 */
export function generateJwtCreds(): JwtCreds {
  // 32-byte (256-bit) secret, hex-encoded — matches HS256 key strength.
  const secret = randomBytes(32).toString("hex");
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 10 * 365 * 24 * 60 * 60; // 10 years
  const anonKey = signJwt(
    { iss: "supabase-demo", role: "anon", iat, exp },
    secret
  );
  const serviceKey = signJwt(
    { iss: "supabase-demo", role: "service_role", iat, exp },
    secret
  );
  return { secret, anonKey, serviceKey };
}

function signJwt(payload: object, secret: string): string {
  const header = { alg: "HS256", typ: "JWT" };
  const h = b64url(JSON.stringify(header));
  const p = b64url(JSON.stringify(payload));
  const data = `${h}.${p}`;
  const sig = b64url(createHmac("sha256", secret).update(data).digest());
  return `${data}.${sig}`;
}

function b64url(input: Buffer | string): string {
  const buf = typeof input === "string" ? Buffer.from(input) : input;
  return buf
    .toString("base64")
    .replace(/=+$/, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}
