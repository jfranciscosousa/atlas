import { useState } from "react";
import { createFileRoute, Link, useRouter } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useForm } from "@tanstack/react-form";

import { AuthError, sessionRequest } from "../lib/auth";
import { Button, buttonVariants } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";

export const Route = createFileRoute("/_public/confirm_new_user/$token")({
  component: ConfirmEmail,
});

function ConfirmEmail() {
  const { token } = Route.useParams();
  const queryClient = useQueryClient();
  const router = useRouter();
  const [confirmed, setConfirmed] = useState(false);
  const [error, setError] = useState("");
  const form = useForm({
    defaultValues: {},
    onSubmit: async () => {
      setError("");
      try {
        await sessionRequest("/auth/user/confirm_new_user", {
          method: "POST",
          queryClient,
          user: { confirm: token },
        });
        await router.invalidate();
        setConfirmed(true);
      } catch (reason) {
        setError(
          reason instanceof AuthError
            ? reason.message
            : "Could not connect. Please try again."
        );
      }
    },
  });

  return (
    <>
      <h1 className="text-3xl font-semibold tracking-tight">
        {confirmed ? "Email confirmed" : "Confirm your email"}
      </h1>
      {confirmed ? (
        <div id="email-confirmed" role="status">
          <p className="mt-4 text-sm leading-7 text-muted-foreground">
            Your email address has been confirmed.
          </p>
          <Link
            to="/campaigns"
            className={buttonVariants({ className: "mt-6" })}
          >
            Continue
          </Link>
        </div>
      ) : (
        <>
          <p className="mt-4 text-sm leading-7 text-muted-foreground">
            Select the button below to confirm your email address.
          </p>
          <form
            id="confirm-email-form"
            className="mt-8 space-y-5"
            onSubmit={event => {
              event.preventDefault();
              void form.handleSubmit();
            }}
          >
            {error && (
              <Alert id="confirmation-error" variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}
            <form.Subscribe selector={state => state.isSubmitting}>
              {submitting => (
                <Button
                  id="confirm-email-submit"
                  type="submit"
                  isLoading={submitting}
                  className="w-full"
                >
                  Confirm email
                </Button>
              )}
            </form.Subscribe>
          </form>
        </>
      )}
    </>
  );
}
