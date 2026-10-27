// Scheduled hard purge for soft-deleted accounts.
//
// The app never deletes immediately: after the email OTP confirm it sets
// profiles.deletion_requested_at and signs the user out. This function runs on
// a schedule (Supabase Dashboard → Edge Functions → Schedules, e.g. daily
// `0 3 * * *`) and deletes every auth user whose 7-day window has elapsed.
// profiles + rooms + storage avatars cascade / are removed here.
//
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto-provided), and
// optional PURGE_SECRET to protect manual invocations.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const expected = Deno.env.get("PURGE_SECRET");
  if (expected) {
    const got = req.headers.get("x-purge-secret");
    if (got !== expected) return json({ error: "Unauthorized" }, 401);
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
    // Remove the avatar folder first; auth.admin.deleteUser cascades DB rows
    // but not storage objects.
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
