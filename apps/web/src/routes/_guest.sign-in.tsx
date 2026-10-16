import { createFileRoute } from "@tanstack/react-router";
import { AuthForm } from "../components/auth-form";

export const Route = createFileRoute("/_guest/sign-in")({
  component: () => <AuthForm mode="sign-in" csrfToken={Route.useRouteContext().csrfToken} />,
});
