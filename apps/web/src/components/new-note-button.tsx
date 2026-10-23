import { useState } from "react";
import { PlusIcon } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";

import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { useNoteCreate } from "../hooks/use-notes";

// There is no creation form: the note exists at once and opens for editing in place.
export function NewNoteButton({
  campaignId,
  characterId,
  children = "New note",
}: {
  campaignId: string;
  /** Links the new note to a character and shares it with that character's player. */
  characterId?: string;
  children?: string;
}) {
  const navigate = useNavigate();
  const create = useNoteCreate(campaignId, characterId);
  // Stays set until the note page is open, so the list never shows between create and navigate.
  const [busy, setBusy] = useState(false);

  async function createAndOpen() {
    setBusy(true);
    try {
      const note = await create.mutateAsync();
      await navigate({
        to: "/campaigns/$campaignId/notes/$noteId",
        params: { campaignId, noteId: note.id },
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
        id={characterId ? `note-new-${characterId}` : "note-new"}
        isLoading={busy}
        disabled={busy}
        onClick={() => void createAndOpen()}
      >
        <PlusIcon aria-hidden="true" data-icon="inline-start" />
        {children}
      </Button>
      {create.error && (
        <Alert id="note-error" variant="destructive">
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
