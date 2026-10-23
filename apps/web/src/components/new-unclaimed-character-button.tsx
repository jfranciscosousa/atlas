import { useState } from "react";
import { UserRoundPlusIcon } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";
import { useForm } from "@tanstack/react-form";

import { Input } from "./ui/input";
import { Field, FieldDescription, FieldLabel } from "./ui/field";
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
import { useUnclaimedCharacterCreate } from "../hooks/use-characters";

/** GM only: prepares a character for a person who has no account yet. */
export function NewUnclaimedCharacterButton({
  campaignId,
}: {
  campaignId: string;
}) {
  const [open, setOpen] = useState(false);
  const navigate = useNavigate();
  const create = useUnclaimedCharacterCreate(campaignId);

  const form = useForm({
    defaultValues: { playerLabel: "" },
    onSubmit: async ({ value }) => {
      try {
        const character = await create.mutateAsync(value.playerLabel.trim());
        setOpen(false);
        form.reset();
        await navigate({
          to: "/campaigns/$campaignId/characters/$characterId",
          params: { campaignId, characterId: character.id },
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
          <Button id="character-new-unclaimed" variant="outline">
            <UserRoundPlusIcon aria-hidden="true" data-icon="inline-start" />
            Prepare a character
          </Button>
        }
      />
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Prepare a character</DialogTitle>
          <DialogDescription>
            Create a character for a player who has no account yet. You write it
            now. The player claims it later with a link, or never, and you keep
            managing it.
          </DialogDescription>
        </DialogHeader>
        <form
          id="unclaimed-character-form"
          className="space-y-4"
          onSubmit={event => {
            event.preventDefault();
            if (!create.isPending) void form.handleSubmit();
          }}
        >
          <form.Field name="playerLabel">
            {field => (
              <Field>
                <FieldLabel htmlFor="character-player-label">
                  Player name
                </FieldLabel>
                <Input
                  id="character-player-label"
                  name="playerLabel"
                  required
                  autoFocus
                  maxLength={100}
                  disabled={create.isPending}
                  value={field.state.value}
                  onChange={event => field.handleChange(event.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="Ana"
                />
                <FieldDescription>
                  Who plays this character. Shown until the player claims it.
                </FieldDescription>
              </Field>
            )}
          </form.Field>
          {create.error && (
            <Alert id="unclaimed-character-error" variant="destructive">
              <AlertDescription>{create.error.message}</AlertDescription>
            </Alert>
          )}
          <DialogFooter>
            <form.Subscribe selector={state => state.values.playerLabel}>
              {label => (
                <Button
                  id="unclaimed-character-create"
                  type="submit"
                  isLoading={create.isPending}
                  disabled={!label.trim()}
                >
                  Create character
                </Button>
              )}
            </form.Subscribe>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
