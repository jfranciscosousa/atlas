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
import { Button, buttonVariants } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { Alert, AlertDescription } from "../components/ui/alert";

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  ssr: false,
  errorComponent: SessionError,
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { name: "referrer", content: "no-referrer" },
      { title: "Atlas" },
    ],
    links: [{ rel: "stylesheet", href: styles }],
  }),
  component: Root,
  shellComponent: Document,
  notFoundComponent: () => (
    <section>
      <h1 className="text-3xl font-semibold">Page not found</h1>
      <Link to="/" className={buttonVariants({ variant: "link", className: "mt-6" })}>
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
          ATLAS
        </Link>
        <Card>
          <CardContent>
            <Outlet />
          </CardContent>
        </Card>
        <p className="mt-6 text-center text-xs text-muted-foreground">
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
      <Alert variant="destructive" className="max-w-md">
        <AlertDescription>Could not connect to the server. Please try again.</AlertDescription>
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
          className={isLoading ? "invisible" : undefined}
          inert={isLoading}
        >
          {children}
        </div>
        <Scripts />
      </body>
    </html>
  );
}
