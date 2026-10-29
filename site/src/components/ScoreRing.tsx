"use client";

import { useEffect, useId, useRef, useState } from "react";
import { colors } from "@/lib/theme";

type Props = {
  score: number;
  size?: number;
  color?: string;
  label: string;
  animate?: boolean;
  className?: string;
};

/** Animated score ring matching lib/widgets/score_ring.dart (1.2s easeOutCubic). */
export function ScoreRing({
  score,
  size = 120,
  color = colors.cyan,
  label,
  animate = true,
  className = "",
}: Props) {
  const [progress, setProgress] = useState(animate ? 0 : 1);
  const gradId = useId();
  const scoreRef = useRef(score);

  useEffect(() => {
    scoreRef.current = score;
    if (!animate) return;

    let raf = 0;
    const start = performance.now();
    const duration = 1200;
    const easeOutCubic = (t: number) => 1 - Math.pow(1 - t, 3);

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      setProgress(easeOutCubic(t));
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [score, animate]);

  const clamped = Math.max(0, Math.min(100, score));
  const pct = (clamped / 100) * (animate ? progress : 1);
  const stroke = size * 0.08;
  const radius = size / 2 - 8;
  const circumference = 2 * Math.PI * radius;
  const dash = circumference * pct;
  const angle = -Math.PI / 2 + 2 * Math.PI * pct;
  const cx = size / 2;
  const cy = size / 2;
  const tipX = cx + radius * Math.cos(angle);
  const tipY = cy + radius * Math.sin(angle);
  const display = Math.round(clamped * (animate ? progress : 1));

  return (
    <div
      className={`relative inline-flex flex-col items-center justify-center ${className}`}
      style={{ width: size, height: size }}
      aria-label={`${label || "Score"} ${display}`}
    >
      <svg width={size} height={size} className="absolute inset-0">
        <defs>
          <linearGradient id={gradId} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor={color} stopOpacity={0.6} />
            <stop offset="100%" stopColor={color} />
          </linearGradient>
          <filter id={`${gradId}-glow`} x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="4" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
        <circle
          cx={cx}
          cy={cy}
          r={radius}
          fill="none"
          stroke={colors.border}
          strokeWidth={stroke}
          strokeLinecap="round"
        />
        <circle
          cx={cx}
          cy={cy}
          r={radius}
          fill="none"
          stroke={`url(#${gradId})`}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${dash} ${circumference}`}
          transform={`rotate(-90 ${cx} ${cy})`}
        />
        {pct > 0.01 && (
          <g filter={`url(#${gradId}-glow)`}>
            <circle cx={tipX} cy={tipY} r={stroke / 2 + 2} fill={color} opacity={0.85} />
            <circle cx={tipX} cy={tipY} r={stroke / 2} fill="#FFFFFF" />
          </g>
        )}
      </svg>
      <div className="relative z-10 flex flex-col items-center leading-none">
        <span
          className="font-extrabold tabular-nums"
          style={{ color, fontSize: size * 0.22 }}
        >
          {display}
        </span>
        {label ? (
          <span
            className="mt-1 font-medium text-ink-secondary text-center px-2"
            style={{ fontSize: Math.max(10, size * 0.1) }}
          >
            {label}
          </span>
        ) : null}
      </div>
    </div>
  );
}
