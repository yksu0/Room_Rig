// Scheduled hard purge for soft-deleted accounts.
//
// The app never deletes immediately: after the email OTP confirm it sets
// profiles.deletion_requested_at (via request_account_deletion RPC or this
// project's soft-delete paths) and signs the user out. This function runs on
// a schedule (pg_cron -> pg_net with the service_role key) and deletes every
// auth user whose 7-day window has elapsed.
//
// Auth: require x-purge-secret (when PURGE_SECRET is set) OR a service_role
// Bearer token. User / anon JWTs are always rejected.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

function bearerToken(req: Request): string | null {
  const auth = req.headers.get("Authorization") ?? "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}

function jwtRole(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length < 2) return null;
    const json = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const payload = JSON.parse(json);
    return typeof payload.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

function isAuthorized(req: Request): boolean {
  const expected = Deno.env.get("PURGE_SECRET");
  const got = req.headers.get("x-purge-secret");
  if (expected && got && got === expected) return true;

  const token = bearerToken(req);
  if (!token) return false;

  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (service && token === service) return true;

  // Accept a JWT whose claim role is service_role (cron / manual admin).
  return jwtRole(token) === "service_role";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!isAuthorized(req)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !service) return json({ error: "Server misconfigured" }, 500);

  const admin = createClient(url, service);

  const { data: due, error: dueErr } = await admin
    .from("profiles_due_for_purge")
    .select("id, deletion_requested_at")
    .limit(200);
  if (dueErr) return json({ error: dueErr.message }, 500);

  const purged: string[] = [];
  const failed: { id: string; error: string }[] = [];

  for (const row of due ?? []) {
    const id = row.id as string;
    try {
      const { data: files } = await admin.storage.from("avatars").list(id);
      if (files && files.length > 0) {
        await admin.storage
          .from("avatars")
          .remove(files.map((f) => `${id}/${f.name}`));
      }
    } catch (_) {
      // Non-fatal: orphaned avatar files are cheap; the user row still goes.
    }
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error) failed.push({ id, error: error.message });
    else purged.push(id);
  }

  return json({ ok: true, purged: purged.length, failed }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
