import { createFileRoute, Link } from "@tanstack/react-router";

export const Route = createFileRoute("/_guest/")({ component: Home });

function Home() {
  return (
    <>
      <h1 className="text-3xl font-semibold tracking-tight">A fresh start.</h1>
      <p className="mt-4 text-sm leading-7 text-emerald-950/65">Create your account or sign in to get started.</p>
      <div className="mt-8 flex flex-wrap items-center gap-5">
        <Link id="sign-up" to="/register" className="primary-button">Create account</Link>
        <Link id="sign-in" to="/sign-in" className="rounded-lg text-sm font-semibold underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4">Sign in</Link>
      </div>
    </>
  );
}
