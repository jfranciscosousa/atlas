import { createFileRoute, Outlet } from "@tanstack/react-router";

import { sessionRequest } from "../lib/auth";
import { AuthLayout } from "../components/auth-layout";

export const Route = createFileRoute("/_public")({
  beforeLoad: async ({ context }) => {
    await sessionRequest("/api/session", { queryClient: context.queryClient });
  },
  component: () => (
    <AuthLayout>
      <Outlet />
    </AuthLayout>
  ),
});
