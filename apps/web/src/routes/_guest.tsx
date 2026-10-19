import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

import { sessionRequest } from "../lib/auth";
import { AuthLayout } from "../components/auth-layout";

export const Route = createFileRoute("/_guest")({
  beforeLoad: async ({ context }) => {
    const session = await sessionRequest("/api/session", {
      queryClient: context.queryClient,
    });
    if (session.user) throw redirect({ to: "/campaigns" });
    return { user: null };
  },
  component: () => (
    <AuthLayout>
      <Outlet />
    </AuthLayout>
  ),
});
