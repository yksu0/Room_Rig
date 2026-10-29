"use client";

import { useEffect, useState } from "react";
import { FadeIn, Section } from "@/components/Section";
import { githubRepo, githubReleasesUrl } from "@/lib/theme";

type ReleaseAsset = {
  name: string;
  browser_download_url: string;
  size: number;
};

type ReleaseInfo = {
  tag: string;
  name: string;
  html_url: string;
  apk: ReleaseAsset | null;
};

export default function DownloadPage() {
  const [info, setInfo] = useState<ReleaseInfo | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(
          `https://api.github.com/repos/${githubRepo}/releases/latest`,
          { headers: { Accept: "application/vnd.github+json" } },
        );
        if (res.status === 404) {
          if (!cancelled) {
            setInfo(null);
            setError(null);
          }
          return;
        }
        if (!res.ok) throw new Error(`GitHub API ${res.status}`);
        const data = (await res.json()) as {
          tag_name: string;
          name: string;
          html_url: string;
          assets: ReleaseAsset[];
        };
        const apk =
          data.assets?.find((a) => a.name.toLowerCase().endsWith(".apk")) ?? null;
        if (!cancelled) {
          setInfo({
            tag: data.tag_name,
            name: data.name || data.tag_name,
            html_url: data.html_url,
            apk,
          });
        }
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <Section eyebrow="Android" title="Download Room Rig">
      <FadeIn>
        <div className="max-w-2xl rounded-rr-xl border border-border bg-card p-6 sm:p-8">
          <p className="text-ink-secondary">
            Room Rig ships as an Android package. Public builds appear on GitHub Releases for{" "}
            <code className="rounded bg-surface px-1.5 py-0.5 text-cyan">{githubRepo}</code>.
            Suggested tag style: <code className="text-ink">v1.0.0+1</code> (not locked).
          </p>

          <div className="mt-6 space-y-3">
            {loading && <p className="text-sm text-ink-muted">Checking latest release…</p>}
            {!loading && error && (
              <p className="text-sm text-amber">Could not reach GitHub: {error}</p>
            )}
            {!loading && !error && info?.apk && (
              <>
                <p className="text-sm text-ink-secondary">
                  Latest: <span className="font-bold text-ink">{info.name}</span> ({info.tag})
                </p>
                <a
                  href={info.apk.browser_download_url}
                  className="inline-flex rounded-rr bg-accent-grad px-5 py-3 text-sm font-extrabold text-black shadow-glow hover:brightness-110"
                >
                  Download {info.apk.name}
                </a>
                <p className="text-xs text-ink-muted">
                  {(info.apk.size / (1024 * 1024)).toFixed(1)} MB
                </p>
              </>
            )}
            {!loading && !error && (!info || !info.apk) && (
              <>
                <p className="rounded-rr border border-border bg-surface-alt p-4 text-sm text-ink-secondary">
                  Release coming soon — no APK asset uploaded yet. The button opens the Releases
                  page (empty until a named tag like v1.0.0+1).
                </p>
                <a
                  href={githubReleasesUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex rounded-rr bg-accent-grad px-5 py-3 text-sm font-extrabold text-black shadow-glow"
                >
                  Open GitHub Releases
                </a>
              </>
            )}
          </div>

          <p className="mt-8 text-sm text-ink-muted">
            Developers with a USB device can still sideload a debug build with{" "}
            <code className="text-ink-secondary">.\scripts\install_android.ps1</code>.
          </p>
        </div>
      </FadeIn>
    </Section>
  );
}
