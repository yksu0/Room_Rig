"use client";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="mx-auto max-w-lg px-4 py-16 text-center">
      <h2 className="text-xl font-extrabold text-ink">Something went wrong</h2>
      <p className="mt-2 text-sm text-ink-secondary">
        {error.message || "An unexpected error occurred."}
      </p>
      <button
        type="button"
        onClick={() => reset()}
        className="mt-6 rounded-rr bg-accent-grad px-4 py-2.5 text-sm font-extrabold text-black"
      >
        Try again
      </button>
    </div>
  );
}
