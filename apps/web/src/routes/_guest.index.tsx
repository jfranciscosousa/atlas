import { createFileRoute, Link } from "@tanstack/react-router";

import { buttonVariants } from "../components/ui/button";

export const Route = createFileRoute("/_guest/")({ component: Home });

function Home() {
  return (
    <>
      <h1 className="text-3xl font-semibold tracking-tight">A fresh start.</h1>
      <p className="mt-4 text-sm leading-7 text-muted-foreground">
        Create your account or sign in to get started.
      </p>
      <div className="mt-8 flex flex-wrap items-center gap-5">
        <Link id="sign-up" to="/register" className={buttonVariants()}>
          Create account
        </Link>
        <Link
          id="sign-in"
          to="/sign-in"
          className={buttonVariants({ variant: "outline" })}
        >
          Sign in
        </Link>
      </div>
    </>
  );
}
