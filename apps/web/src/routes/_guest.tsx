import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

import { sessionRequest } from "../lib/auth";

export const Route = createFileRoute("/_guest")({
  beforeLoad: async ({ context }) => {
    const session = await sessionRequest("/api/session", {
      queryClient: context.queryClient,
    });
    if (session.user) throw redirect({ to: "/dashboard" });
    return { user: null };
  },
  component: Outlet,
});
