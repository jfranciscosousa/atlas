import { createFileRoute, Link } from "@tanstack/react-router";

import { profileQueryOptions } from "../hooks/use-profile";
import { buttonVariants } from "../components/ui/button";
import { ProfileForm } from "../components/profile-form";

export const Route = createFileRoute("/_authenticated/profile")({
  loader: async ({ context }) => {
    await context.queryClient.ensureQueryData(
      profileQueryOptions(context.user.id)
    );
  },
  component: Profile,
});

function Profile() {
  const { user } = Route.useRouteContext();
  return (
    <>
      <Link
        to="/dashboard"
        className={buttonVariants({ variant: "link", className: "mb-5 px-0" })}
      >
        Back to dashboard
      </Link>
      <h1 className="text-3xl font-semibold tracking-tight">Your profile</h1>
      <p className="mt-3 text-sm text-muted-foreground">
        Choose your name and profile photo.
      </p>
      <ProfileForm key={user.id} userId={user.id} />
    </>
  );
}
