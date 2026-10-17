import { createFileRoute } from "@tanstack/react-router";
import { AuthForm } from "../components/auth-form";

export const Route = createFileRoute("/_guest/reset")({
  component: () => <AuthForm mode="reset-request" />,
});
