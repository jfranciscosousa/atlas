import { createRouter } from "@tanstack/react-router";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

import { routeTree } from "./routeTree.gen";
import { pollWhileActive } from "./lib/polling";

export function getRouter() {
  // Changes from other people arrive by polling. React Query polls only the queries that a mounted
  // component reads. The server render has no person, so it does not poll.
  const queryClient = new QueryClient({
    defaultOptions: { queries: { refetchOnWindowFocus: "always" } },
  });
  if (typeof document !== "undefined") {
    const defaults = queryClient.getDefaultOptions();
    queryClient.setDefaultOptions({
      ...defaults,
      queries: {
        ...defaults.queries,
        refetchInterval: pollWhileActive(queryClient, window),
      },
    });
  }

  return createRouter({
    routeTree,
    context: { queryClient },
    Wrap: ({ children }) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    ),
    scrollRestoration: true,
  });
}

declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof getRouter>;
  }
}
