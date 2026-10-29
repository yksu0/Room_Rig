"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { createClient } from "@/lib/supabase/client";
import { fetchIsAdmin, fetchOwnProfile } from "@/lib/auth";

const links = [
  { href: "/", label: "Product" },
  { href: "/community", label: "Community" },
  { href: "/download", label: "Download" },
];

export function SiteNav() {
  const pathname = usePathname();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState<string | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const sb = createClient();
        const { data } = await sb.auth.getSession();
        const user = data.session?.user;
        if (!user) {
          if (!cancelled) {
            setLabel(null);
            setIsAdmin(false);
          }
          return;
        }
        const [profile, admin] = await Promise.all([
          fetchOwnProfile(user.id),
          fetchIsAdmin(user.id),
        ]);
        if (!cancelled) {
          setLabel(profile?.display_name || user.email || "Signed in");
          setIsAdmin(admin);
        }
      } catch {
        if (!cancelled) {
          setLabel(null);
          setIsAdmin(false);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [pathname]);

  async function signOut() {
    const sb = createClient();
    await sb.auth.signOut();
    setLabel(null);
    setIsAdmin(false);
    router.replace("/");
  }

  const navLinks = [
    ...links,
    ...(isAdmin ? [{ href: "/admin", label: "Admin" }] : []),
  ];

  return (
    <header className="sticky top-0 z-50 glass">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
        <Link href="/" className="text-lg font-extrabold tracking-tight text-ink">
          Room <span className="text-cyan">Rig</span>
        </Link>

        <nav className="hidden items-center gap-6 md:flex" aria-label="Primary">
          {navLinks.map((l) => {
            const active = pathname === l.href;
            return (
              <Link
                key={l.href}
                href={l.href}
                className={`text-sm font-semibold transition-colors ${
                  active ? "text-ink" : "text-ink-secondary hover:text-cyan"
                }`}
                aria-current={active ? "page" : undefined}
              >
                {l.label}
              </Link>
            );
          })}
          {label ? (
            <div className="flex items-center gap-2">
              <span className="max-w-[10rem] truncate text-sm text-ink-muted">{label}</span>
              <button
                type="button"
                onClick={signOut}
                className="rounded-rr border border-border px-3 py-1.5 text-sm font-semibold text-ink-secondary hover:border-cyan/50 hover:text-cyan"
              >
                Sign out
              </button>
            </div>
          ) : (
            <Link
              href="/auth"
              className="rounded-rr bg-accent-grad px-3.5 py-1.5 text-sm font-extrabold text-black shadow-glow"
            >
              Sign in
            </Link>
          )}
        </nav>

        <button
          type="button"
          className="md:hidden rounded-rr border border-border p-2 text-cyan"
          aria-label="Toggle menu"
          onClick={() => setOpen((v) => !v)}
        >
          <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            {open ? (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            ) : (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            )}
          </svg>
        </button>
      </div>

      <AnimatePresence>
        {open && (
          <motion.nav
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="overflow-hidden border-t border-border md:hidden"
            aria-label="Mobile"
          >
            <div className="flex flex-col gap-1 px-4 py-3">
              {navLinks.map((l) => (
                <Link
                  key={l.href}
                  href={l.href}
                  onClick={() => setOpen(false)}
                  className="rounded-rr px-3 py-2.5 text-sm font-semibold text-ink-secondary hover:bg-card hover:text-cyan"
                >
                  {l.label}
                </Link>
              ))}
              {label ? (
                <button
                  type="button"
                  onClick={() => {
                    setOpen(false);
                    void signOut();
                  }}
                  className="rounded-rr px-3 py-2.5 text-left text-sm font-semibold text-ink-secondary hover:bg-card hover:text-cyan"
                >
                  Sign out ({label})
                </button>
              ) : (
                <Link
                  href="/auth"
                  onClick={() => setOpen(false)}
                  className="rounded-rr bg-accent-grad px-3 py-2.5 text-center text-sm font-extrabold text-black"
                >
                  Sign in
                </Link>
              )}
            </div>
          </motion.nav>
        )}
      </AnimatePresence>
    </header>
  );
}
