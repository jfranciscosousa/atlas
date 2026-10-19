import { createFileRoute } from "@tanstack/react-router";

import { profileQueryOptions } from "../hooks/use-profile";
import { ProfileForm } from "../components/profile-form";
import { PageHeader } from "../components/page-header";

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
    <div className="mx-auto max-w-2xl space-y-8">
      <PageHeader
        crumbs={[
          { label: "Campaigns", to: "/campaigns" },
          { label: "Profile" },
        ]}
        title="Your profile"
        description="Choose your name and profile photo."
      />
      <div className="rounded-2xl border bg-card p-6 shadow-xs sm:p-8">
        <ProfileForm key={user.id} userId={user.id} />
      </div>
    </div>
  );
}
