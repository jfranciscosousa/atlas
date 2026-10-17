import {
  createRootRouteWithContext,
  HeadContent,
  Link,
  Outlet,
  Scripts,
  useRouter,
  useRouterState,
} from "@tanstack/react-router";
import { useEffect, useState, type ReactNode } from "react";
import type { QueryClient } from "@tanstack/react-query";
import styles from "../styles.css?url";
import { LoadingScreen } from "../components/loading-screen";

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  ssr: false,
  errorComponent: SessionError,
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { name: "referrer", content: "no-referrer" },
      { title: "Lemonade Stand" },
    ],
    links: [{ rel: "stylesheet", href: styles }],
  }),
  component: Root,
  shellComponent: Document,
  notFoundComponent: () => (
    <section>
      <h1 className="text-3xl font-semibold">Page not found</h1>
      <Link to="/" className="mt-6 inline-block underline">
        Back to home
      </Link>
    </section>
  ),
});

function Root() {
  return (
    <main className="flex min-h-screen items-center justify-center px-5 py-12">
      <div className="w-full max-w-md">
        <Link
          to="/"
          className="mb-8 flex items-center justify-center gap-3 text-sm font-semibold tracking-wide"
        >
          <span
            aria-hidden="true"
            className="flex size-9 items-center justify-center rounded-full bg-amber-200 text-lg"
          >
            L
          </span>
          LEMONADE STAND
        </Link>
        <section className="rounded-3xl border border-emerald-950/10 bg-white p-7 shadow-[0_16px_60px_-36px_#143c3055] sm:p-10">
          <Outlet />
        </section>
        <p className="mt-6 text-center text-xs text-emerald-950/70">
          A fresh start, one step at a time.
        </p>
      </div>
    </main>
  );
}

function SessionError() {
  const router = useRouter();
  return (
    <main className="flex min-h-screen items-center justify-center px-5">
      <div role="alert">
        <p>Could not connect to the server. Please try again.</p>
        <button
          onClick={() => void router.invalidate()}
          className="mt-4 font-semibold underline"
        >
          Try again
        </button>
      </div>
    </main>
  );
}

function Document({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [hasResolved, setHasResolved] = useState(false);
  const isPending = useRouterState({
    select: (state) => state.isLoading || state.status === "pending",
  });

  useEffect(
    () => router.subscribe("onResolved", () => setHasResolved(true)),
    [router],
  );

  const isLoading = !hasResolved || isPending;

  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        {isLoading && <LoadingScreen />}

        <div
          className={isLoading ? "invisible" : "page-enter"}
          inert={isLoading}
        >
          {children}
        </div>
        <Scripts />
      </body>
    </html>
  );
}
