"use client";

import type { ReactNode } from "react";

/**
 * Visible-by-default entrance. Uses CSS animation (not whileInView opacity:0),
 * so full-page screenshots and no-JS still show content. Honors reduced motion.
 */
export function FadeIn({
  children,
  className = "",
  delay = 0,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
}) {
  return (
    <div
      className={`fade-up ${className}`}
      style={{ animationDelay: `${Math.max(0, delay)}s` }}
    >
      {children}
    </div>
  );
}

export function Section({
  id,
  eyebrow,
  title,
  children,
  className = "",
}: {
  id?: string;
  eyebrow?: string;
  title?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section id={id} className={`mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-20 ${className}`}>
      {(eyebrow || title) && (
        <div className="mb-10 fade-up">
          {eyebrow ? (
            <p className="mb-2 text-xs font-bold uppercase tracking-[0.22em] text-cyan">{eyebrow}</p>
          ) : null}
          {title ? (
            <h2 className="text-balance text-3xl font-extrabold tracking-tight text-ink sm:text-4xl">
              {title}
            </h2>
          ) : null}
        </div>
      )}
      {children}
    </section>
  );
}
