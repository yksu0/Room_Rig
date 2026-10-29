"use client";

import Image from "next/image";
import { motion } from "framer-motion";

const tabs = [
  { id: "hub", label: "Hub", icon: "⌂" },
  { id: "room", label: "Room", icon: "▦" },
  { id: "scan", label: "Scan", icon: "◎" },
  { id: "bench", label: "Benchmark", icon: "◔" },
];

export function PhoneMock() {
  return (
    <motion.div
      initial={false}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
      className="relative mx-auto w-[260px] sm:w-[300px]"
    >
      <div className="absolute -inset-6 rounded-[2.5rem] bg-cyan/10 blur-2xl" aria-hidden />
      <div className="relative overflow-hidden rounded-[2rem] border border-border bg-surface shadow-glow-strong ring-1 ring-cyan/20">
        <div className="flex items-center justify-between px-4 pt-3 pb-2">
          <span className="text-[10px] font-bold uppercase tracking-[0.18em] text-cyan">
            Room Rig
          </span>
          <span className="text-[10px] text-ink-muted">9:41</span>
        </div>
        <div className="relative mx-2 overflow-hidden rounded-rr-lg border border-border bg-card">
          <Image
            src="/app-screenshot.jpg"
            alt="Room Rig room editor with 3D layout viewport"
            width={720}
            height={1280}
            className="h-[340px] w-full object-cover object-top sm:h-[400px]"
            priority
          />
          <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-surface to-transparent" />
        </div>
        <div className="grid grid-cols-4 gap-1 px-2 py-3">
          {tabs.map((t, i) => (
            <div
              key={t.id}
              className={`flex flex-col items-center gap-0.5 rounded-lg py-1.5 text-[10px] font-semibold ${
                i === 1 ? "text-cyan" : "text-ink-muted"
              }`}
            >
              <span className="text-sm leading-none">{t.icon}</span>
              {t.label}
              {i === 1 ? <span className="mt-0.5 h-0.5 w-6 rounded-full bg-cyan" /> : null}
            </div>
          ))}
        </div>
      </div>
    </motion.div>
  );
}
