import type { QueryClient } from "@tanstack/react-query";

import { useEffect, useState, type ReactNode } from "react";
import {
  createRootRouteWithContext,
  HeadContent,
  Link,
  Outlet,
  Scripts,
  useRouter,
  useRouterState,
} from "@tanstack/react-router";

import styles from "../styles.css?url";
import { THEME_INIT_SCRIPT } from "../lib/theme";
import { Button, buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { LoadingScreen } from "../components/loading-screen";
import "../hooks/use-theme";

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()(
  {
    ssr: false,
    errorComponent: SessionError,
    head: () => ({
      meta: [
        { charSet: "utf-8" },
        {
          name: "viewport",
          content:
            "width=device-width, initial-scale=1, interactive-widget=resizes-content",
        },
        { name: "referrer", content: "no-referrer" },
        { title: "Atlas" },
      ],
      links: [
        { rel: "stylesheet", href: styles },
        { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" },
      ],
      scripts: [{ children: THEME_INIT_SCRIPT }],
    }),
    component: Root,
    shellComponent: Document,
    notFoundComponent: () => (
      <section className="flex min-h-[60vh] flex-col items-center justify-center gap-2 px-6 text-center">
        <p className="text-sm font-medium text-muted-foreground">404</p>
        <h1 className="text-3xl font-semibold">Page not found</h1>
        <p className="text-sm text-muted-foreground">
          This part of the map is still blank.
        </p>
        <Link to="/" className={buttonVariants({ className: "mt-4" })}>
          Back to home
        </Link>
      </section>
    ),
  }
);

function Root() {
  return <Outlet />;
}

function SessionError() {
  const router = useRouter();
  return (
    <main className="flex min-h-screen items-center justify-center px-5">
      <Alert variant="destructive" className="max-w-md">
        <AlertDescription>
          Could not connect to the server. Please try again.
        </AlertDescription>
        <Button variant="outline" onClick={() => void router.invalidate()}>
          Try again
        </Button>
      </Alert>
    </main>
  );
}

function Document({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [hasResolved, setHasResolved] = useState(false);
  const isPending = useRouterState({
    select: state => state.status === "pending",
  });
  // A filter change updates the search, not the page. Only a new path is a page change.
  const pageChanging = useRouterState({
    select: state =>
      state.status === "pending" &&
      state.location.pathname !== state.resolvedLocation?.pathname,
  });
  const [showProgress, setShowProgress] = useState(false);

  useEffect(() => {
    if (!pageChanging) return;
    // A fast page change never shows the bar: a short flash reads as flicker.
    const timer = setTimeout(() => setShowProgress(true), 300);
    return () => {
      clearTimeout(timer);
      setShowProgress(false);
    };
  }, [pageChanging]);

  useEffect(
    () => router.subscribe("onResolved", () => setHasResolved(true)),
    [router]
  );

  // Only the first load hides the app, until the page itself has rendered.
  // Later navigations keep the shell on screen.
  const [revealed, setRevealed] = useState(false);
  useEffect(() => {
    if (hasResolved && !isPending) setRevealed(true);
  }, [hasResolved, isPending]);
  const isLoading = !revealed;

  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <HeadContent />
      </head>
      <body>
        {isLoading && <LoadingScreen />}

        {revealed && showProgress && (
          <div
            role="progressbar"
            aria-label="Loading page"
            className="fixed inset-x-0 top-0 z-50 h-0.5 animate-pulse bg-primary"
          />
        )}
        <div className={isLoading ? "invisible" : undefined} inert={isLoading}>
          {children}
        </div>
        <Scripts />
      </body>
    </html>
  );
}
