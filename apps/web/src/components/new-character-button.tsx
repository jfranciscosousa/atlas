import { useState } from "react";
import { PlusIcon } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";

import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { useCharacterCreate } from "../hooks/use-characters";

// There is no creation form: the character exists at once, unnamed, and opens in place.
export function NewCharacterButton({
  campaignId,
  children = "New character",
}: {
  campaignId: string;
  children?: string;
}) {
  const navigate = useNavigate();
  const create = useCharacterCreate(campaignId);
  // Stays set until the character page is open, so the list never shows between create and navigate.
  const [busy, setBusy] = useState(false);

  async function createAndOpen() {
    setBusy(true);
    try {
      const character = await create.mutateAsync();
      await navigate({
        to: "/campaigns/$campaignId/characters/$characterId",
        params: { campaignId, characterId: character.id },
      });
    } catch {
      // The mutation exposes the error below.
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col items-end gap-2">
      <Button
        id="character-new"
        isLoading={busy}
        disabled={busy}
        onClick={() => void createAndOpen()}
      >
        <PlusIcon aria-hidden="true" data-icon="inline-start" />
        {children}
      </Button>
      {create.error && (
        <Alert id="character-error" variant="destructive">
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
