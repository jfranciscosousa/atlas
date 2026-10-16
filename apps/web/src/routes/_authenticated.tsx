import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { sessionRequest } from "../lib/auth";

export const Route = createFileRoute("/_authenticated")({
  beforeLoad: async () => {
    const session = await sessionRequest("/api/session");
    if (!session.user) throw redirect({ to: "/sign-in" });
    return { user: session.user, csrfToken: session.csrfToken };
  },
  component: Outlet,
});
