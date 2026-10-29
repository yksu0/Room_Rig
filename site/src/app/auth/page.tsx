"use client";

import { FormEvent, Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { FadeIn, Section } from "@/components/Section";
import { createClient } from "@/lib/supabase/client";
import { fetchIsAdmin } from "@/lib/auth";

function AuthForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [signUp, setSignUp] = useState(() => searchParams.get("mode") === "signup");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const sb = createClient();
        const { data } = await sb.auth.getSession();
        const user = data.session?.user;
        if (!user || cancelled) return;
        const admin = await fetchIsAdmin(user.id);
        if (!cancelled) router.replace(admin ? "/admin" : "/");
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [router]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setStatus(signUp ? "Creating account…" : "Signing in…");
    try {
      const sb = createClient();
      if (signUp) {
        const { error } = await sb.auth.signUp({
          email,
          password,
          options: { emailRedirectTo: `${window.location.origin}/auth` },
        });
        if (error) throw error;
        setStatus("Check your email to confirm, or sign in if confirm is off.");
      } else {
        const { data, error } = await sb.auth.signInWithPassword({ email, password });
        if (error) throw error;
        const admin = data.user ? await fetchIsAdmin(data.user.id) : false;
        router.replace(admin ? "/admin" : "/");
      }
    } catch (err) {
      setStatus(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function google() {
    setBusy(true);
    setStatus("Redirecting to Google…");
    try {
      const sb = createClient();
      const { error } = await sb.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo: `${window.location.origin}/auth` },
      });
      if (error) throw error;
    } catch (err) {
      setStatus(err instanceof Error ? err.message : String(err));
      setBusy(false);
    }
  }

  return (
    <Section eyebrow="Account" title={signUp ? "Sign up" : "Sign in"}>
      <FadeIn>
        <p className="mb-6 max-w-xl text-sm text-ink-secondary">
          Sign in to sync your Room Rig account across devices. Use email or Google — same login
          the Android app uses for Community.
        </p>
        <form
          onSubmit={onSubmit}
          className="max-w-md space-y-4 rounded-rr-xl border border-border bg-card p-6"
        >
          <label className="block text-sm font-semibold text-ink-secondary">
            Email
            <input
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1.5 w-full rounded-rr border border-border bg-surface px-3 py-2.5 text-ink outline-none focus:border-cyan"
            />
          </label>
          <label className="block text-sm font-semibold text-ink-secondary">
            Password
            <input
              type="password"
              required
              minLength={6}
              autoComplete={signUp ? "new-password" : "current-password"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1.5 w-full rounded-rr border border-border bg-surface px-3 py-2.5 text-ink outline-none focus:border-cyan"
            />
          </label>
          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-rr bg-accent-grad py-3 text-sm font-extrabold text-black disabled:opacity-60"
          >
            {signUp ? "Create account" : "Sign in"}
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={google}
            className="w-full rounded-rr border border-border py-3 text-sm font-bold text-ink-secondary hover:border-cyan/40 hover:text-cyan disabled:opacity-60"
          >
            Continue with Google
          </button>
          <button
            type="button"
            className="text-sm font-semibold text-cyan hover:underline"
            onClick={() => setSignUp((v) => !v)}
          >
            {signUp ? "Already have an account? Sign in" : "Need an account? Sign up"}
          </button>
          <p className="min-h-5 text-sm text-amber" role="status">
            {status}
          </p>
        </form>
        <p className="mt-4 text-xs text-ink-muted">
          Redirect allow-list includes <code>https://roomrig.vercel.app/**</code>.
        </p>
      </FadeIn>
    </Section>
  );
}

export default function AuthPage() {
  return (
    <Suspense
      fallback={
        <Section title="Sign in">
          <p className="text-ink-muted">Loading…</p>
        </Section>
      }
    >
      <AuthForm />
    </Suspense>
  );
}
