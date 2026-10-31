import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

import {
  authRedirect,
  consumeAuthRedirect,
  rememberAuthRedirect,
} from "../lib/redirect";
import { sessionRequest } from "../lib/auth";
import { AuthLayout } from "../components/auth-layout";

export const Route = createFileRoute("/_guest")({
  beforeLoad: async ({ context, location, preload }) => {
    const destination = (location.search as Record<string, unknown>).redirect;
    if (!preload) rememberAuthRedirect(destination);
    const session = await sessionRequest("/api/session", {
      queryClient: context.queryClient,
    });
    if (session.user)
      throw redirect({
        href: preload
          ? authRedirect(destination)
          : consumeAuthRedirect(destination),
      });
    return { user: null };
  },
  component: () => (
    <AuthLayout>
      <Outlet />
    </AuthLayout>
  ),
});
