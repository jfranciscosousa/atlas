import { useState } from "react";
import { PlusIcon } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { ENTRY_ICONS } from "./entry-icons";
import {
  ENTRY_KIND_LABELS,
  ENTRY_KINDS,
  type EntryKind,
} from "../lib/entry-kinds";
import { useEntryCreate } from "../hooks/use-entries";

// The entry exists at once, hidden, with a name to change, and opens for editing in place.
export function NewEntryButton({
  campaignId,
  kind,
  children = "New entry",
}: {
  campaignId: string;
  /** Creates this kind at once. Without it the button offers the six kinds. */
  kind?: EntryKind;
  children?: string;
}) {
  const navigate = useNavigate();
  const create = useEntryCreate(campaignId);
  // Stays set until the entry page is open, so the list never shows between create and navigate.
  const [busy, setBusy] = useState(false);

  async function createAndOpen(chosen: EntryKind) {
    setBusy(true);
    try {
      const entry = await create.mutateAsync({
        kind: chosen,
        name: `Unnamed ${ENTRY_KIND_LABELS[chosen].label}`,
      });
      await navigate({
        to: "/campaigns/$campaignId/entries/$entryId",
        params: { campaignId, entryId: entry.id },
      });
    } catch {
      // The mutation exposes the error below.
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col items-end gap-2">
      {kind ? (
        <Button
          id="entry-new"
          isLoading={busy}
          disabled={busy}
          onClick={() => void createAndOpen(kind)}
        >
          <PlusIcon aria-hidden="true" data-icon="inline-start" />
          {children}
        </Button>
      ) : (
        <DropdownMenu>
          <DropdownMenuTrigger
            render={<Button id="entry-new" isLoading={busy} disabled={busy} />}
          >
            <PlusIcon aria-hidden="true" data-icon="inline-start" />
            {children}
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-40">
            {ENTRY_KINDS.map(entryKind => {
              const Icon = ENTRY_ICONS[entryKind];
              return (
                <DropdownMenuItem
                  key={entryKind}
                  id={`entry-new-${entryKind}`}
                  onClick={() => void createAndOpen(entryKind)}
                >
                  <Icon aria-hidden="true" />
                  {ENTRY_KIND_LABELS[entryKind].label}
                </DropdownMenuItem>
              );
            })}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
      {create.error && (
        <Alert id="entry-error" variant="destructive">
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
