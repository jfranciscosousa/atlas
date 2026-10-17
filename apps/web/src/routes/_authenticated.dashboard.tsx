import { useState } from "react";
import { createFileRoute, useRouter } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";

import { sessionRequest } from "../lib/auth";
import { todosQueryOptions } from "../hooks/use-todos";
import { Button } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";
import { TodoList } from "../components/todo-list";

export const Route = createFileRoute("/_authenticated/dashboard")({
  loader: async ({ context }) => {
    await context.queryClient.ensureQueryData(
      todosQueryOptions(context.user.id)
    );
  },
  component: Dashboard,
});

function Dashboard() {
  const { user } = Route.useRouteContext();
  const queryClient = useQueryClient();
  const router = useRouter();
  const [error, setError] = useState("");
  const [signingOut, setSigningOut] = useState(false);

  async function signOut() {
    setError("");
    setSigningOut(true);
    try {
      await sessionRequest("/api/session", {
        method: "DELETE",
        queryClient,
      });
      await queryClient.cancelQueries();
      queryClient.clear();
      await router.invalidate();
    } catch {
      setError("Could not sign out. Please try again.");
    } finally {
      setSigningOut(false);
    }
  }

  return (
    <>
      <h1 className="text-3xl font-semibold tracking-tight">Welcome back.</h1>
      <p className="mt-4 text-sm leading-7 text-muted-foreground">
        You are signed in as{" "}
        <strong
          id="current-user-email"
          className="font-medium break-all text-foreground"
        >
          {user.email}
        </strong>
        .
      </p>
      <TodoList key={user.id} userId={user.id} />
      {error && (
        <Alert variant="destructive" className="mt-4">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="mt-8">
        <Button
          id="sign-out"
          type="button"
          onClick={signOut}
          disabled={signingOut}
          variant="outline"
        >
          {signingOut ? "Signing out…" : "Sign out"}
        </Button>
      </div>
    </>
  );
}
