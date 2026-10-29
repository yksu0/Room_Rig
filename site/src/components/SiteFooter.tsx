import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex max-w-6xl flex-col gap-3 px-4 py-10 text-sm text-ink-muted sm:flex-row sm:items-center sm:justify-between sm:px-6">
        <p>
          Room Rig · product on Android · auth via Supabase ·{" "}
          <Link href="/admin" className="text-cyan hover:underline">
            Admin
          </Link>
        </p>
        <p className="font-medium text-ink-secondary">Treat your room like a PC build.</p>
      </div>
    </footer>
  );
}
