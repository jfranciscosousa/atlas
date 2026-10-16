import { useState } from "react";
import { createFileRoute, useRouter } from "@tanstack/react-router";
import { sessionRequest } from "../lib/auth";

export const Route = createFileRoute("/_authenticated/dashboard")({ component: Dashboard });

function Dashboard() {
  const { user, csrfToken } = Route.useRouteContext();
  const router = useRouter();
  const [error, setError] = useState("");
  const [signingOut, setSigningOut] = useState(false);

  async function signOut() {
    setError("");
    setSigningOut(true);
    try {
      await sessionRequest("/api/session", { method: "DELETE", csrfToken });
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
        You are signed in as <strong id="current-user-email" className="break-all font-medium text-emerald-950">{user.email}</strong>.
      </p>
      {error && <p role="alert" className="mt-4 text-sm text-red-700">{error}</p>}
      <div className="mt-8">
        <button id="sign-out" type="button" onClick={signOut} disabled={signingOut} className="primary-button">
          {signingOut ? "Signing out…" : "Sign out"}
        </button>
      </div>
    </>
  );
}
