"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { FadeIn, Section } from "@/components/Section";
import { createClient } from "@/lib/supabase/client";
import { fetchIsAdmin } from "@/lib/auth";
import type { LayoutRatingStats, PublishedLayout } from "@/lib/types";

type Row = PublishedLayout & { stats?: LayoutRatingStats | null };

const emptyBaseline = {
  title: "",
  description: "",
  tags: "baseline",
  layoutJson: '{\n  "room": { "width": 3.6, "depth": 4.8 },\n  "furniture": []\n}',
  scoresJson: '{\n  "airflow": 70,\n  "lighting": 72,\n  "ergonomics": 68,\n  "spatial": 74\n}',
};

export default function AdminPage() {
  const [gate, setGate] = useState<"loading" | "signed-out" | "denied" | "ok">("loading");
  const [rows, setRows] = useState<Row[]>([]);
  const [monthly, setMonthly] = useState<PublishedLayout[]>([]);
  const [status, setStatus] = useState("");
  const [baselineForm, setBaselineForm] = useState(emptyBaseline);
  const [editingId, setEditingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    const sb = createClient();
    const { data: sessionData } = await sb.auth.getSession();
    const user = sessionData.session?.user;
    if (!user) {
      setGate("signed-out");
      return;
    }
    const admin = await fetchIsAdmin(user.id);
    if (!admin) {
      setGate("denied");
      return;
    }
    setGate("ok");

    const [layoutsRes, statsRes, monthlyRes] = await Promise.all([
      sb
        .from("published_layouts")
        .select(
          "id, author_id, title, description, layout, scores, tags, is_admin_baseline, featured_until, published_at, hidden",
        )
        .order("published_at", { ascending: false })
        .limit(100),
      sb.from("layout_rating_stats").select("*"),
      sb.from("monthly_featured_layouts").select("*"),
    ]);

    if (layoutsRes.error) {
      setStatus(
        `Load warning: ${layoutsRes.error.message}. Admin SELECT for hidden rows needs the RLS migration.`,
      );
    }

    const statsMap = new Map(
      ((statsRes.data ?? []) as LayoutRatingStats[]).map((s) => [s.layout_id, s]),
    );
    const list = ((layoutsRes.data ?? []) as PublishedLayout[]).map((r) => ({
      ...r,
      stats: statsMap.get(r.id) ?? null,
    }));
    setRows(list);
    setMonthly((monthlyRes.data ?? []) as PublishedLayout[]);
  }, []);

  useEffect(() => {
    let cancelled = false;
    queueMicrotask(() => {
      if (!cancelled) void load();
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  const baselines = useMemo(() => rows.filter((r) => r.is_admin_baseline), [rows]);
  const community = useMemo(() => rows.filter((r) => !r.is_admin_baseline), [rows]);

  async function toggleHidden(row: Row) {
    setStatus("Updating hidden…");
    const sb = createClient();
    const { error } = await sb
      .from("published_layouts")
      .update({ hidden: !row.hidden })
      .eq("id", row.id);
    setStatus(error ? `Hide failed: ${error.message} (apply admin_rls.sql)` : "Updated.");
    await load();
  }

  async function setFeatured(row: Row, clear: boolean) {
    setStatus(clear ? "Clearing featured…" : "Featuring for 30 days…");
    const sb = createClient();
    const featured_until = clear
      ? null
      : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
    const { error } = await sb.from("published_layouts").update({ featured_until }).eq("id", row.id);
    setStatus(error ? `Feature failed: ${error.message} (apply admin_rls.sql)` : "Updated.");
    await load();
  }

  async function deleteBaseline(id: string) {
    if (!confirm("Delete this baseline?")) return;
    setStatus("Deleting…");
    const sb = createClient();
    const { error } = await sb.from("published_layouts").delete().eq("id", id);
    setStatus(error ? `Delete failed: ${error.message}` : "Deleted.");
    await load();
  }

  async function saveBaseline(e: FormEvent) {
    e.preventDefault();
    setStatus("Saving baseline…");
    let layout: unknown;
    let scores: unknown;
    try {
      layout = JSON.parse(baselineForm.layoutJson);
      scores = JSON.parse(baselineForm.scoresJson);
    } catch {
      setStatus("Invalid JSON in layout or scores.");
      return;
    }
    const payload = {
      title: baselineForm.title.trim(),
      description: baselineForm.description.trim() || null,
      tags: baselineForm.tags
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean),
      layout,
      scores,
      is_admin_baseline: true,
      author_id: null as string | null,
      hidden: false,
    };
    const sb = createClient();
    const { error } = editingId
      ? await sb.from("published_layouts").update(payload).eq("id", editingId)
      : await sb.from("published_layouts").insert(payload);
    if (error) {
      setStatus(`Baseline save failed: ${error.message} (apply admin_rls.sql)`);
    } else {
      setStatus(editingId ? "Baseline updated." : "Baseline created.");
      setBaselineForm(emptyBaseline);
      setEditingId(null);
      await load();
    }
  }

  function startEdit(row: Row) {
    setEditingId(row.id);
    setBaselineForm({
      title: row.title,
      description: row.description ?? "",
      tags: (row.tags ?? []).join(", "),
      layoutJson: JSON.stringify(row.layout ?? {}, null, 2),
      scoresJson: JSON.stringify(row.scores ?? {}, null, 2),
    });
  }

  if (gate === "loading") {
    return (
      <Section title="Admin">
        <p className="text-ink-muted">Checking access…</p>
      </Section>
    );
  }

  if (gate === "signed-out") {
    return (
      <Section title="Admin">
        <p className="mb-4 text-ink-secondary">Sign in required.</p>
        <Link href="/auth" className="rounded-rr bg-accent-grad px-4 py-2.5 text-sm font-extrabold text-black">
          Sign in
        </Link>
      </Section>
    );
  }

  if (gate === "denied") {
    return (
      <Section title="Admin">
        <div className="max-w-xl rounded-rr-lg border border-border bg-card p-5 text-sm text-ink-secondary">
          This account is not flagged as admin. After the security fix,{" "}
          <code className="text-cyan">public.is_admin()</code> must return true for your user
          (profiles.is_admin via SECURITY DEFINER — not client-writable).
        </div>
      </Section>
    );
  }

  return (
    <Section eyebrow="Admin" title="Community curation">
      <FadeIn>
        <p className="mb-2 max-w-3xl text-sm text-ink-secondary">
          Hide posts, feature layouts, and manage baselines. Write actions require{" "}
          <code className="text-cyan">admin_rls.sql</code> applied on Supabase.
        </p>
        <p className="mb-8 min-h-5 text-sm text-amber" role="status">
          {status}
        </p>
      </FadeIn>

      <div className="mb-12">
        <h3 className="mb-3 text-lg font-extrabold text-ink">Monthly top 3 (derived)</h3>
        {monthly.length === 0 ? (
          <p className="text-sm text-ink-muted">No monthly featured rows yet.</p>
        ) : (
          <ul className="grid gap-3 sm:grid-cols-3">
            {monthly.map((m) => (
              <li key={m.id} className="rounded-rr border border-border bg-card p-4 text-sm">
                <p className="font-bold text-ink">{m.title}</p>
                <p className="text-ink-muted">{new Date(m.published_at).toLocaleDateString()}</p>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="mb-12">
        <h3 className="mb-3 text-lg font-extrabold text-ink">Community posts</h3>
        <div className="overflow-x-auto rounded-rr-lg border border-border">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-surface-alt text-ink-muted">
              <tr>
                <th className="px-3 py-2 font-semibold">Title</th>
                <th className="px-3 py-2 font-semibold">Votes</th>
                <th className="px-3 py-2 font-semibold">Featured</th>
                <th className="px-3 py-2 font-semibold">Hidden</th>
                <th className="px-3 py-2 font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody>
              {community.map((row) => (
                <tr key={row.id} className="border-t border-border/80">
                  <td className="px-3 py-2.5 font-semibold text-ink">{row.title}</td>
                  <td className="px-3 py-2.5 text-ink-secondary">
                    {row.stats
                      ? `▲${row.stats.up_count} ▼${row.stats.down_count} (net ${row.stats.net_score})`
                      : "—"}
                  </td>
                  <td className="px-3 py-2.5 text-ink-muted">
                    {row.featured_until
                      ? new Date(row.featured_until).toLocaleDateString()
                      : "—"}
                  </td>
                  <td className="px-3 py-2.5">{row.hidden ? "yes" : "no"}</td>
                  <td className="px-3 py-2.5">
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => void toggleHidden(row)}
                        className="rounded border border-border px-2 py-1 text-xs font-bold hover:border-cyan/50 hover:text-cyan"
                      >
                        {row.hidden ? "Unhide" : "Hide"}
                      </button>
                      <button
                        type="button"
                        onClick={() => void setFeatured(row, false)}
                        className="rounded border border-border px-2 py-1 text-xs font-bold hover:border-cyan/50 hover:text-cyan"
                      >
                        Feature 30d
                      </button>
                      {row.featured_until ? (
                        <button
                          type="button"
                          onClick={() => void setFeatured(row, true)}
                          className="rounded border border-border px-2 py-1 text-xs font-bold hover:border-cyan/50 hover:text-cyan"
                        >
                          Clear feature
                        </button>
                      ) : null}
                    </div>
                  </td>
                </tr>
              ))}
              {community.length === 0 ? (
                <tr>
                  <td colSpan={5} className="px-3 py-4 text-ink-muted">
                    No community posts loaded.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>

      <div className="grid gap-8 lg:grid-cols-2">
        <div>
          <h3 className="mb-3 text-lg font-extrabold text-ink">
            {editingId ? "Edit baseline" : "Create baseline"}
          </h3>
          <form onSubmit={saveBaseline} className="space-y-3 rounded-rr-lg border border-border bg-card p-4">
            <input
              required
              placeholder="Title"
              value={baselineForm.title}
              onChange={(e) => setBaselineForm((f) => ({ ...f, title: e.target.value }))}
              className="w-full rounded-rr border border-border bg-surface px-3 py-2 text-sm outline-none focus:border-cyan"
            />
            <input
              placeholder="Description"
              value={baselineForm.description}
              onChange={(e) => setBaselineForm((f) => ({ ...f, description: e.target.value }))}
              className="w-full rounded-rr border border-border bg-surface px-3 py-2 text-sm outline-none focus:border-cyan"
            />
            <input
              placeholder="Tags (comma-separated)"
              value={baselineForm.tags}
              onChange={(e) => setBaselineForm((f) => ({ ...f, tags: e.target.value }))}
              className="w-full rounded-rr border border-border bg-surface px-3 py-2 text-sm outline-none focus:border-cyan"
            />
            <label className="block text-xs font-bold uppercase tracking-wider text-ink-muted">
              Layout JSON
              <textarea
                required
                rows={8}
                value={baselineForm.layoutJson}
                onChange={(e) => setBaselineForm((f) => ({ ...f, layoutJson: e.target.value }))}
                className="mt-1 w-full rounded-rr border border-border bg-surface px-3 py-2 font-mono text-xs outline-none focus:border-cyan"
              />
            </label>
            <label className="block text-xs font-bold uppercase tracking-wider text-ink-muted">
              Scores JSON
              <textarea
                required
                rows={5}
                value={baselineForm.scoresJson}
                onChange={(e) => setBaselineForm((f) => ({ ...f, scoresJson: e.target.value }))}
                className="mt-1 w-full rounded-rr border border-border bg-surface px-3 py-2 font-mono text-xs outline-none focus:border-cyan"
              />
            </label>
            <div className="flex gap-2">
              <button type="submit" className="rounded-rr bg-accent-grad px-4 py-2 text-sm font-extrabold text-black">
                {editingId ? "Update" : "Create"}
              </button>
              {editingId ? (
                <button
                  type="button"
                  onClick={() => {
                    setEditingId(null);
                    setBaselineForm(emptyBaseline);
                  }}
                  className="rounded-rr border border-border px-4 py-2 text-sm font-bold text-ink-secondary"
                >
                  Cancel
                </button>
              ) : null}
            </div>
          </form>
        </div>

        <div>
          <h3 className="mb-3 text-lg font-extrabold text-ink">Baselines</h3>
          <ul className="space-y-3">
            {baselines.map((b) => (
              <li key={b.id} className="rounded-rr border border-border bg-surface-alt p-4">
                <p className="font-bold text-ink">{b.title}</p>
                <p className="text-xs text-ink-muted">{b.id}</p>
                <div className="mt-2 flex gap-2">
                  <button
                    type="button"
                    onClick={() => startEdit(b)}
                    className="rounded border border-border px-2 py-1 text-xs font-bold hover:text-cyan"
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    onClick={() => void deleteBaseline(b.id)}
                    className="rounded border border-red/40 px-2 py-1 text-xs font-bold text-red"
                  >
                    Delete
                  </button>
                </div>
              </li>
            ))}
            {baselines.length === 0 ? (
              <li className="text-sm text-ink-muted">No baselines loaded.</li>
            ) : null}
          </ul>
        </div>
      </div>
    </Section>
  );
}
