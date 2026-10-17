import { createFileRoute } from "@tanstack/react-router";

import { AuthForm } from "../components/auth-form";

export const Route = createFileRoute("/_public/password-reset/$token")({
  component: () => (
    <AuthForm mode="reset-password" token={Route.useParams().token} />
  ),
});
