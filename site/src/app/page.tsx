"use client";

import Link from "next/link";
import { FadeIn, Section } from "@/components/Section";
import { PhoneMock } from "@/components/PhoneMock";
import { ScoreRing } from "@/components/ScoreRing";
import { ChairIcon, DeskIcon, FanIcon, LampIcon } from "@/components/icons/FurnitureIcons";
import { domains } from "@/lib/theme";

const loop = [
  {
    name: "Hub",
    detail: "See every room at a glance — score rings, history, and what to improve next.",
    icon: (
      <svg viewBox="0 0 32 32" className="h-7 w-7" fill="none" aria-hidden>
        <path d="M6 14 L16 6 L26 14 V26 H6 Z" stroke="currentColor" strokeWidth="2" fill="currentColor" fillOpacity="0.15" />
        <path d="M12 26 V18 H20 V26" stroke="currentColor" strokeWidth="2" />
      </svg>
    ),
  },
  {
    name: "Room",
    detail: "Drag furniture in 2D or 3D, then let Auto-Rig suggest a cleaner layout.",
    icon: (
      <svg viewBox="0 0 32 32" className="h-7 w-7" fill="none" aria-hidden>
        <rect x="5" y="8" width="22" height="16" rx="2" stroke="currentColor" strokeWidth="2" fill="currentColor" fillOpacity="0.15" />
        <path d="M5 20 H27 M14 8 V24" stroke="currentColor" strokeWidth="1.6" opacity="0.7" />
      </svg>
    ),
  },
  {
    name: "Scan",
    detail: "Point the camera for a rough seed of your space when the scene cooperates.",
    icon: (
      <svg viewBox="0 0 32 32" className="h-7 w-7" fill="none" aria-hidden>
        <circle cx="16" cy="16" r="7" stroke="currentColor" strokeWidth="2" fill="currentColor" fillOpacity="0.12" />
        <circle cx="16" cy="16" r="2.5" fill="currentColor" />
        <path d="M8 8 H11 M8 8 V11 M24 8 H21 M24 8 V11 M8 24 H11 M8 24 V21 M24 24 H21 M24 24 V21" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    name: "Benchmark",
    detail: "Score airflow, light, comfort, and space — then browse Community layouts.",
    icon: (
      <svg viewBox="0 0 32 32" className="h-7 w-7" fill="none" aria-hidden>
        <circle cx="16" cy="16" r="10" stroke="currentColor" strokeWidth="2" fill="currentColor" fillOpacity="0.1" />
        <path d="M16 8 V16 L22 19" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      </svg>
    ),
  },
];

const domainVisual: Record<string, { Icon: typeof FanIcon; score: number }> = {
  airflow: { Icon: FanIcon, score: 78 },
  lighting: { Icon: LampIcon, score: 88 },
  ergonomics: { Icon: ChairIcon, score: 74 },
  spatial: { Icon: DeskIcon, score: 81 },
};

const scoringSteps = [
  { n: "01", title: "Place", body: "Build your room with real furniture footprints." },
  { n: "02", title: "Score", body: "Four domain rings update from the layout — not magic." },
  { n: "03", title: "Compare", body: "Benchmark modes and Community layouts side by side." },
  { n: "04", title: "Apply", body: "Pull improvements back into the live room." },
];

const communityPreview = [
  { title: "Gaming Setup", tag: "Baseline", score: 70, tint: "#00E5FF" },
  { title: "Home Office", tag: "Baseline", score: 77, tint: "#8B7CFF" },
  { title: "This month’s top", tag: "Featured", score: 84, tint: "#FFD666" },
];

export default function HomePage() {
  return (
    <>
      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="pointer-events-none absolute inset-0 soft-grid opacity-70" aria-hidden />
        <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-4 pb-10 pt-12 sm:px-6 lg:grid-cols-2 lg:gap-16 lg:pt-16">
          <div>
            <p className="fade-up mb-3 text-xs font-bold uppercase tracking-[0.28em] text-cyan">
              Android room optimizer
            </p>
            <h1 className="fade-up text-balance text-4xl font-extrabold tracking-tight text-ink sm:text-5xl lg:text-6xl">
              Treat your room like a{" "}
              <span className="bg-accent-grad bg-clip-text text-transparent">PC build.</span>
            </h1>
            <p
              className="fade-up mt-4 max-w-xl text-xl font-semibold text-ink"
              style={{ animationDelay: "0.05s" }}
            >
              Layout it. Score it. Make it better.
            </p>
            <p
              className="fade-up mt-3 max-w-xl text-base leading-relaxed text-ink-secondary sm:text-lg"
              style={{ animationDelay: "0.1s" }}
            >
              Room Rig helps you arrange furniture for airflow, lighting, comfort, and space — then
              shows clear scores so you know what actually improved.
            </p>
            <div className="fade-up mt-8 flex flex-wrap gap-3" style={{ animationDelay: "0.15s" }}>
              <Link
                href="/download"
                className="rounded-rr bg-accent-grad px-5 py-3 text-sm font-extrabold text-black shadow-glow transition hover:brightness-110"
              >
                Get the Android APK
              </Link>
              <Link
                href="/auth"
                className="rounded-rr border border-border px-5 py-3 text-sm font-bold text-ink-secondary transition hover:border-cyan/50 hover:text-cyan"
              >
                Create a free account
              </Link>
            </div>

            <div className="mt-10 flex flex-wrap gap-4">
              <ScoreRing score={86} label="Overall" size={104} />
              <ScoreRing score={78} label="Airflow" color="#00E5FF" size={104} />
              <ScoreRing score={91} label="Lighting" color="#FFD666" size={104} />
            </div>
          </div>

          <PhoneMock />
        </div>
      </section>

      {/* Loop */}
      <div className="section-glow">
        <Section id="loop" eyebrow="The loop" title="Four steps. One clearer room.">
          <div className="relative z-[1] grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {loop.map((step, i) => (
              <FadeIn key={step.name} delay={i * 0.05}>
                <article className="group flex h-full flex-col rounded-rr-lg border border-border bg-card-grad p-5 transition hover:border-cyan/45 hover:shadow-glow">
                  <div className="mb-4 flex items-center justify-between">
                    <span className="flex h-11 w-11 items-center justify-center rounded-rr bg-cyan/12 text-cyan">
                      {step.icon}
                    </span>
                    <span className="text-xs font-bold tabular-nums text-ink-muted">0{i + 1}</span>
                  </div>
                  <h3 className="text-lg font-extrabold text-ink">{step.name}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-secondary">{step.detail}</p>
                </article>
              </FadeIn>
            ))}
          </div>
        </Section>
      </div>

      {/* Domains */}
      <Section id="benchmark" eyebrow="Benchmark domains" title="Four scores. One honest layout.">
        <div className="grid gap-4 md:grid-cols-2">
          {domains.map((d, i) => {
            const vis = domainVisual[d.id];
            const Icon = vis.Icon;
            return (
              <FadeIn key={d.id} delay={i * 0.05}>
                <article
                  className="relative overflow-hidden rounded-rr-lg border bg-surface-alt/70 p-6 backdrop-blur-sm transition hover:bg-card"
                  style={{ borderColor: `${d.color}66` }}
                >
                  <div
                    className="pointer-events-none absolute -right-8 -top-10 h-36 w-36 rounded-full opacity-30 blur-2xl"
                    style={{ background: d.color }}
                    aria-hidden
                  />
                  <div className="relative flex items-start justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="mb-3 flex items-center gap-3">
                        <span
                          className="flex h-10 w-10 items-center justify-center rounded-rr border"
                          style={{ color: d.color, borderColor: `${d.color}55`, background: `${d.color}14` }}
                        >
                          <Icon className="h-6 w-6" />
                        </span>
                        <h3 className="text-xl font-extrabold" style={{ color: d.color }}>
                          {d.label}
                        </h3>
                      </div>
                      <p className="text-sm leading-relaxed text-ink-secondary">{d.blurb}</p>
                    </div>
                    <ScoreRing score={vis.score} size={84} color={d.color} label="" />
                  </div>
                </article>
              </FadeIn>
            );
          })}
        </div>
      </Section>

      {/* Scoring strip */}
      <section className="relative border-y border-border/80 bg-surface/40">
        <div className="pointer-events-none absolute inset-0 soft-grid opacity-40" aria-hidden />
        <div className="relative mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-20">
          <FadeIn>
            <p className="mb-2 text-xs font-bold uppercase tracking-[0.22em] text-cyan">How scoring works</p>
            <h2 className="mb-10 text-balance text-3xl font-extrabold tracking-tight text-ink sm:text-4xl">
              From placement to a number you can trust enough to act on.
            </h2>
          </FadeIn>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {scoringSteps.map((s, i) => (
              <FadeIn key={s.n} delay={i * 0.05}>
                <div className="h-full rounded-rr-lg border border-border bg-card/80 p-5">
                  <p className="text-xs font-extrabold tracking-widest text-cyan">{s.n}</p>
                  <h3 className="mt-2 text-lg font-extrabold text-ink">{s.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-secondary">{s.body}</p>
                </div>
              </FadeIn>
            ))}
          </div>
        </div>
      </section>

      {/* Community preview */}
      <Section
        id="community-preview"
        eyebrow="Community"
        title="Steal a better layout — or share yours."
      >
        <FadeIn>
          <p className="mb-8 max-w-2xl text-ink-secondary">
            Browse baselines and featured rooms from Benchmark → Community. Clone into your account,
            compare scores, then apply what works.
          </p>
        </FadeIn>
        <div className="grid gap-4 sm:grid-cols-3">
          {communityPreview.map((c, i) => (
            <FadeIn key={c.title} delay={i * 0.05}>
              <article className="flex items-center gap-4 rounded-rr-lg border border-border bg-card p-4 transition hover:border-cyan/40 hover:shadow-glow">
                <ScoreRing score={c.score} size={72} color={c.tint} label="" />
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-wider text-cyan">{c.tag}</p>
                  <h3 className="font-extrabold text-ink">{c.title}</h3>
                  <p className="text-xs text-ink-muted">Preview · open in app</p>
                </div>
              </article>
            </FadeIn>
          ))}
        </div>
        <FadeIn delay={0.15}>
          <Link
            href="/community"
            className="mt-6 inline-flex rounded-rr border border-border px-4 py-2.5 text-sm font-bold text-ink-secondary hover:border-cyan/45 hover:text-cyan"
          >
            Browse Community on the web →
          </Link>
        </FadeIn>
      </Section>

      {/* Honesty */}
      <Section id="honesty" eyebrow="Honesty limits" title="Estimates, not lab instruments.">
        <FadeIn>
          <div className="rounded-rr-xl border border-border bg-card/90 p-6 sm:p-8">
            <p className="max-w-3xl text-base leading-relaxed text-ink-secondary">
              Benchmark scores are layout estimates — not CFD, radiosity, or survey-grade scan.
              Prices are mid-market PH estimates with a published basis. We show the limits so you
              can decide with clear eyes.
            </p>
            <p className="mt-4 text-sm text-ink-muted">
              Price basis:{" "}
              <a
                className="font-semibold text-cyan hover:underline"
                href="https://github.com/yksu0/Room_Rig/blob/main/assets/PRICE_SOURCES.md"
                target="_blank"
                rel="noopener noreferrer"
              >
                PRICE_SOURCES.md
              </a>
            </p>
          </div>
        </FadeIn>
      </Section>

      {/* Final CTA */}
      <section className="relative mx-auto max-w-6xl px-4 pb-20 sm:px-6">
        <FadeIn>
          <div className="relative overflow-hidden rounded-rr-xl border border-cyan/30 bg-card-grad px-6 py-10 text-center shadow-glow sm:px-12 sm:py-14">
            <div
              className="pointer-events-none absolute inset-0 opacity-80"
              style={{
                background:
                  "radial-gradient(600px 240px at 50% 0%, rgba(0,229,255,0.16), transparent 70%)",
              }}
              aria-hidden
            />
            <div className="relative">
              <h2 className="text-balance text-3xl font-extrabold text-ink sm:text-4xl">
                Ready to score your room?
              </h2>
              <p className="mx-auto mt-3 max-w-xl text-ink-secondary">
                Install the Android build, create an account, and run your first Benchmark in
                minutes.
              </p>
              <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
                <Link
                  href="/download"
                  className="rounded-rr bg-accent-grad px-6 py-3 text-sm font-extrabold text-black shadow-glow hover:brightness-110"
                >
                  Download APK
                </Link>
                <Link
                  href="/auth?mode=signup"
                  className="rounded-rr border border-border px-6 py-3 text-sm font-bold text-ink-secondary hover:border-cyan/50 hover:text-cyan"
                >
                  Sign up free
                </Link>
              </div>
            </div>
          </div>
        </FadeIn>
      </section>
    </>
  );
}
