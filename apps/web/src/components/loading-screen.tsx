import { Spinner } from "./ui/spinner";

export function LoadingScreen() {
  return (
    <div
      role="status"
      className="fixed inset-0 flex items-center justify-center bg-background"
    >
      <Spinner aria-hidden="true" />
      <span className="sr-only">Loading…</span>
    </div>
  );
}
