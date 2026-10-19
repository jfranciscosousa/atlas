import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

import { safeRedirect } from "../lib/redirect";
import { sessionRequest } from "../lib/auth";
import { AuthLayout } from "../components/auth-layout";

export const Route = createFileRoute("/_guest")({
  beforeLoad: async ({ context, location }) => {
    const session = await sessionRequest("/api/session", {
      queryClient: context.queryClient,
    });
    if (session.user)
      throw redirect({
        href:
          safeRedirect((location.search as Record<string, unknown>).redirect) ??
          "/campaigns",
      });
    return { user: null };
  },
  component: () => (
    <AuthLayout>
      <Outlet />
    </AuthLayout>
  ),
});
