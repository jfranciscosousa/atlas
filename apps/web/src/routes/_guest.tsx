import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { sessionRequest } from "../lib/auth";

export const Route = createFileRoute("/_guest")({
  beforeLoad: async () => {
    const session = await sessionRequest("/api/session");
    if (session.user) throw redirect({ to: "/dashboard" });
    return { user: null, csrfToken: session.csrfToken };
  },
  component: Outlet,
});
