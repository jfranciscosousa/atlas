import { useState } from "react";
import { createFileRoute, useRouter } from "@tanstack/react-router";
import { sessionRequest } from "../lib/auth";
import { useQueryClient } from "@tanstack/react-query";
import { TodoList } from "../components/todo-list";
import { todosQueryOptions } from "../hooks/use-todos";

export const Route = createFileRoute("/_authenticated/dashboard")({
  loader: async ({ context }) => {
    await context.queryClient.ensureQueryData(todosQueryOptions(context.user.id));
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
      <p className="mt-4 text-sm leading-7 text-emerald-950/65">
        You are signed in as{" "}
        <strong
          id="current-user-email"
          className="break-all font-medium text-emerald-950"
        >
          {user.email}
        </strong>
        .
      </p>
      <TodoList key={user.id} userId={user.id} />
      {error && (
        <p role="alert" className="mt-4 text-sm text-red-700">
          {error}
        </p>
      )}
      <div className="mt-8">
        <button
          id="sign-out"
          type="button"
          onClick={signOut}
          disabled={signingOut}
          className="primary-button"
        >
          {signingOut ? "Signing out…" : "Sign out"}
        </button>
      </div>
    </>
  );
}
