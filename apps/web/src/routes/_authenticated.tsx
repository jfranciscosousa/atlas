import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";

import { sessionRequest } from "../lib/auth";
import { profileQueryOptions } from "../hooks/use-profile";
import { campaignsQueryOptions } from "../hooks/use-campaigns";
import { AppShell } from "../components/app-shell";

export const Route = createFileRoute("/_authenticated")({
  beforeLoad: async ({ context, location }) => {
    const session = await sessionRequest("/api/session", {
      queryClient: context.queryClient,
    });
    if (!session.user)
      throw redirect({ to: "/sign-in", search: { redirect: location.href } });
    return { user: session.user };
  },
  // The shell shows the campaign list and the signed-in person's name.
  loader: async ({ context }) => {
    await Promise.all([
      context.queryClient.ensureQueryData(
        campaignsQueryOptions(context.user.id)
      ),
      context.queryClient.ensureQueryData(profileQueryOptions(context.user.id)),
    ]);
  },
  component: Shell,
});

function Shell() {
  const { user } = Route.useRouteContext();
  return (
    <AppShell user={user}>
      <Outlet />
    </AppShell>
  );
}
