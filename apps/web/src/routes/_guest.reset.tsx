import { createFileRoute } from "@tanstack/react-router";

import { safeRedirect } from "../lib/redirect";
import { AuthForm } from "../components/auth-form";

export const Route = createFileRoute("/_guest/reset")({
  validateSearch: (search: Record<string, unknown>): { redirect?: string } => {
    const redirect = safeRedirect(search.redirect);
    return redirect ? { redirect } : {};
  },
  component: () => (
    <AuthForm mode="reset-request" redirect={Route.useSearch().redirect} />
  ),
});
