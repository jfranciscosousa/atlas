import { useState, type ComponentProps } from "react";
import { PlusIcon } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";
import { useForm } from "@tanstack/react-form";

import { Input } from "./ui/input";
import { Field, FieldLabel } from "./ui/field";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "./ui/dialog";
import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { useCampaignCreate } from "../hooks/use-campaigns";

export function NewCampaignButton({
  userId,
  children = "New campaign",
  ...buttonProps
}: { userId: string } & Omit<ComponentProps<typeof Button>, "onClick">) {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();
  const create = useCampaignCreate(userId);

  const form = useForm({
    defaultValues: { name: "" },
    onSubmit: async ({ value }) => {
      try {
        const campaign = await create.mutateAsync(value.name.trim());
        setOpen(false);
        form.reset();
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
    <Dialog
      open={open}
      onOpenChange={next => {
        setOpen(next);
        if (!next) create.reset();
      }}
    >
      <DialogTrigger
        render={
          <Button id="campaign-new" {...buttonProps}>
            <PlusIcon aria-hidden="true" data-icon="inline-start" />
            {children}
          </Button>
        }
      />
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New campaign</DialogTitle>
          <DialogDescription>
            Name your campaign. You become its GM and can fill in the rest
            later.
          </DialogDescription>
        </DialogHeader>
        <form
          id="campaign-form"
          className="space-y-4"
          onSubmit={event => {
            event.preventDefault();
            if (!create.isPending) void form.handleSubmit();
          }}
        >
          <form.Field name="name">
            {field => (
              <Field>
                <FieldLabel htmlFor="campaign-name">Campaign name</FieldLabel>
                <Input
                  id="campaign-name"
                  name="name"
                  required
                  autoFocus
                  maxLength={200}
                  disabled={create.isPending}
                  value={field.state.value}
                  onChange={event => field.handleChange(event.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="The Sunken Keep"
                />
              </Field>
            )}
          </form.Field>
          {create.error && (
            <Alert id="campaign-error" variant="destructive">
              <AlertDescription>{create.error.message}</AlertDescription>
            </Alert>
          )}
          <DialogFooter>
            <form.Subscribe selector={state => state.values.name}>
              {name => (
                <Button
                  id="campaign-create"
                  type="submit"
                  isLoading={create.isPending}
                  disabled={!name.trim()}
                >
                  Create campaign
                </Button>
              )}
            </form.Subscribe>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
