export default function Loading() {
  return (
    <div className="mx-auto max-w-5xl px-4 py-16">
      <div className="h-8 w-40 animate-pulse rounded bg-surface-alt" />
      <div className="mt-6 h-4 w-2/3 max-w-md animate-pulse rounded bg-surface-alt" />
      <div className="mt-3 h-4 w-1/2 max-w-sm animate-pulse rounded bg-surface-alt" />
    </div>
  );
}
