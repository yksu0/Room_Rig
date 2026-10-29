"use client";

import { useEffect, useState } from "react";
import { FadeIn, Section } from "@/components/Section";
import { ScoreRing } from "@/components/ScoreRing";
import { createClient } from "@/lib/supabase/client";
import type { PublishedLayout, LayoutRatingStats, CommunityProfile } from "@/lib/types";

type Card = PublishedLayout & {
  stats?: LayoutRatingStats | null;
  author?: CommunityProfile | null;
};

function overallScore(scores: Record<string, number> | null | undefined): number {
  if (!scores) return 0;
  const vals = Object.values(scores).filter((n) => typeof n === "number");
  if (!vals.length) return 0;
  return Math.round(vals.reduce((a, b) => a + b, 0) / vals.length);
}

export default function CommunityPage() {
  const [featured, setFeatured] = useState<Card[]>([]);
  const [baselines, setBaselines] = useState<Card[]>([]);
  const [blocked, setBlocked] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const sb = createClient();

        const baselinesRes = await sb
          .from("published_layouts")
          .select(
            "id, author_id, title, description, layout, scores, tags, is_admin_baseline, featured_until, published_at, hidden",
          )
          .eq("is_admin_baseline", true)
          .eq("hidden", false)
          .order("published_at", { ascending: false });

        if (baselinesRes.error) {
          if (!cancelled) {
            setBlocked(
              `Anonymous read is blocked or unavailable (${baselinesRes.error.message}). Sign in on the app, or ask an admin to confirm SELECT policies for non-hidden layouts.`,
            );
          }
          return;
        }

        const monthlyRes = await sb.from("monthly_featured_layouts").select("*");
        const featuredManualRes = await sb
          .from("published_layouts")
          .select(
            "id, author_id, title, description, layout, scores, tags, is_admin_baseline, featured_until, published_at, hidden",
          )
          .eq("hidden", false)
          .eq("is_admin_baseline", false)
          .gt("featured_until", new Date().toISOString())
          .order("featured_until", { ascending: false })
          .limit(6);

        const baselineRows = (baselinesRes.data ?? []) as PublishedLayout[];
        const monthlyRows = (monthlyRes.data ?? []) as PublishedLayout[];
        const manualRows = (featuredManualRes.data ?? []) as PublishedLayout[];

        const byId = new Map<string, PublishedLayout>();
        for (const row of [...monthlyRows, ...manualRows]) byId.set(row.id, row);
        const featuredRows = Array.from(byId.values());

        const ids = [...baselineRows, ...featuredRows].map((r) => r.id);
        const authorIds = [
          ...new Set(
            [...baselineRows, ...featuredRows]
              .map((r) => r.author_id)
              .filter((id): id is string => Boolean(id)),
          ),
        ];

        const [statsRes, authorsRes] = await Promise.all([
          ids.length
            ? sb.from("layout_rating_stats").select("*").in("layout_id", ids)
            : Promise.resolve({ data: [] as LayoutRatingStats[], error: null }),
          authorIds.length
            ? sb.from("community_profiles").select("id, display_name, avatar_url").in("id", authorIds)
            : Promise.resolve({ data: [] as CommunityProfile[], error: null }),
        ]);

        const statsMap = new Map(
          ((statsRes.data ?? []) as LayoutRatingStats[]).map((s) => [s.layout_id, s]),
        );
        const authorMap = new Map(
          ((authorsRes.data ?? []) as CommunityProfile[]).map((a) => [a.id, a]),
        );

        const hydrate = (rows: PublishedLayout[]): Card[] =>
          rows.map((r) => ({
            ...r,
            stats: statsMap.get(r.id) ?? null,
            author: r.author_id ? authorMap.get(r.author_id) ?? null : null,
          }));

        if (!cancelled) {
          setBaselines(hydrate(baselineRows));
          setFeatured(hydrate(featuredRows));
          setBlocked(null);
        }
      } catch (e) {
        if (!cancelled) {
          setBlocked(e instanceof Error ? e.message : String(e));
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <Section eyebrow="Community" title="Featured layouts & baselines">
      <FadeIn>
        <p className="mb-8 max-w-2xl text-ink-secondary">
          Read-only preview of what the app shows in Benchmark → Community. Publish, rate, and
          clone stay in the Android app.
        </p>
      </FadeIn>

      {loading && <p className="text-sm text-ink-muted">Loading Community…</p>}
      {blocked && (
        <div className="rounded-rr-lg border border-amber/40 bg-amber/10 p-5 text-sm text-amber">
          {blocked}
        </div>
      )}

      {!loading && !blocked && (
        <div className="space-y-12">
          <div>
            <h3 className="mb-4 text-lg font-extrabold text-ink">This month&apos;s top & featured</h3>
            {featured.length === 0 ? (
              <p className="text-sm text-ink-muted">No featured layouts yet.</p>
            ) : (
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {featured.map((card, i) => (
                  <FadeIn key={card.id} delay={i * 0.05}>
                    <LayoutCard card={card} />
                  </FadeIn>
                ))}
              </div>
            )}
          </div>

          <div>
            <h3 className="mb-4 text-lg font-extrabold text-ink">Admin baselines</h3>
            {baselines.length === 0 ? (
              <p className="text-sm text-ink-muted">No baselines published.</p>
            ) : (
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {baselines.map((card, i) => (
                  <FadeIn key={card.id} delay={i * 0.05}>
                    <LayoutCard card={card} baseline />
                  </FadeIn>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </Section>
  );
}

function LayoutCard({ card, baseline }: { card: Card; baseline?: boolean }) {
  const score = overallScore(card.scores as Record<string, number> | null);
  return (
    <article className="flex h-full flex-col rounded-rr-lg border border-border bg-card p-5 transition hover:border-cyan/35 hover:shadow-glow">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-wider text-cyan">
            {baseline ? "Baseline" : "Featured"}
          </p>
          <h4 className="mt-1 text-base font-extrabold text-ink">{card.title}</h4>
          {card.author?.display_name ? (
            <p className="mt-1 text-xs text-ink-muted">by {card.author.display_name}</p>
          ) : null}
        </div>
        <ScoreRing score={score || 70} size={64} label="" />
      </div>
      {card.description ? (
        <p className="mb-3 line-clamp-3 text-sm text-ink-secondary">{card.description}</p>
      ) : null}
      <div className="mt-auto flex flex-wrap gap-2 text-xs text-ink-muted">
        {(card.tags ?? []).slice(0, 4).map((t) => (
          <span key={t} className="rounded-full border border-border px-2 py-0.5">
            {t}
          </span>
        ))}
        {card.stats ? (
          <span className="ml-auto font-semibold text-ink-secondary">
            ▲ {card.stats.up_count} · ▼ {card.stats.down_count}
          </span>
        ) : null}
      </div>
    </article>
  );
}
