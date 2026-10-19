import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useForm } from "@tanstack/react-form";

import {
  campaignsQueryOptions,
  useCampaignCreate,
  useCampaignsList,
} from "../hooks/use-campaigns";
import { Input } from "../components/ui/input";
import { Field, FieldLabel } from "../components/ui/field";
import {
  Empty,
  EmptyHeader,
  EmptyTitle,
  EmptyDescription,
} from "../components/ui/empty";
import { buttonVariants, Button } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";

export const Route = createFileRoute("/_authenticated/campaigns/")({
  loader: async ({ context }) => {
    await context.queryClient.ensureQueryData(
      campaignsQueryOptions(context.user.id)
    );
  },
  component: Campaigns,
});

function Campaigns() {
  const { user } = Route.useRouteContext();
  const navigate = useNavigate();
  const campaigns = useCampaignsList(user.id).data;
  const create = useCampaignCreate(user.id);

  const form = useForm({
    defaultValues: { name: "" },
    onSubmit: async ({ value }) => {
      try {
        const campaign = await create.mutateAsync(value.name.trim());
        await navigate({
          to: "/campaigns/$campaignId",
          params: { campaignId: campaign.id },
        });
      } catch {
        // The mutation exposes the error below and keeps the name for retry.
      }
    },
  });

  return (
    <>
      <Link
        to="/dashboard"
        className={buttonVariants({ variant: "link", className: "mb-5 px-0" })}
      >
        Back to dashboard
      </Link>
      <h1 className="text-3xl font-semibold tracking-tight">Campaigns</h1>
      <form
        id="campaign-form"
        className="mt-6"
        onSubmit={event => {
          event.preventDefault();
          if (!create.isPending) void form.handleSubmit();
        }}
      >
        <form.Field name="name">
          {field => (
            <Field>
              <FieldLabel htmlFor="campaign-name">Campaign name</FieldLabel>
              <div className="flex gap-2">
                <Input
                  id="campaign-name"
                  name="name"
                  required
                  maxLength={200}
                  disabled={create.isPending}
                  value={field.state.value}
                  onChange={event => field.handleChange(event.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="The Sunken Keep"
                  className="min-w-0 flex-1"
                />
                <Button
                  id="campaign-create"
                  type="submit"
                  isLoading={create.isPending}
                  disabled={!field.state.value.trim()}
                >
                  Create campaign
                </Button>
              </div>
            </Field>
          )}
        </form.Field>
      </form>
      {create.error && (
        <Alert id="campaign-error" variant="destructive" className="mt-4">
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
      {campaigns.length === 0 ? (
        <Empty id="campaigns-empty" className="mt-6 p-6">
          <EmptyHeader>
            <EmptyTitle>No campaigns yet</EmptyTitle>
            <EmptyDescription>
              Create your first campaign above. You become its GM.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <ul id="campaign-list" className="mt-6 divide-y divide-border">
          {campaigns.map(campaign => (
            <li key={campaign.id} className="py-3">
              <Link
                id={`campaign-${campaign.id}`}
                to="/campaigns/$campaignId"
                params={{ campaignId: campaign.id }}
                className="font-medium hover:underline"
              >
                {campaign.name}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
