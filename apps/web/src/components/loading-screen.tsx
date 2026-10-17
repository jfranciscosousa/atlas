export function LoadingScreen() {
  return (
    <div role="status" className="fixed inset-0 flex items-center justify-center bg-[#fcfaf3]">
      <span aria-hidden="true" className="size-6 rounded-full border-2 border-emerald-950/15 border-t-emerald-900 motion-safe:animate-spin" />
      <span className="sr-only">Loading…</span>
    </div>
  );
}
