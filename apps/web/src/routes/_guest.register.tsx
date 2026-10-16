import { createFileRoute } from "@tanstack/react-router";
import { AuthForm } from "../components/auth-form";

export const Route = createFileRoute("/_guest/register")({
  component: () => <AuthForm mode="register" csrfToken={Route.useRouteContext().csrfToken} />,
});
