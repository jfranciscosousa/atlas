import { createFileRoute } from "@tanstack/react-router";

import { safeRedirect } from "../lib/redirect";
import { AuthForm } from "../components/auth-form";

export const Route = createFileRoute("/_guest/sign-in")({
  validateSearch: (search: Record<string, unknown>): { redirect?: string } => {
    const redirect = safeRedirect(search.redirect);
    return redirect ? { redirect } : {};
  },
  component: Page,
});

function Page() {
  const { redirect } = Route.useSearch();
  return <AuthForm mode="sign-in" redirect={redirect} />;
}
