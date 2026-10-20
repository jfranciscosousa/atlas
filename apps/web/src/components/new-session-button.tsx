import { useState } from "react";
import { PlusIcon } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";

import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { useSessionCreate } from "../hooks/use-sessions";

// There is no creation form: the session exists at once with the next number and opens in place.
export function NewSessionButton({
  campaignId,
  children = "New session",
}: {
  campaignId: string;
  children?: string;
}) {
  const navigate = useNavigate();
  const create = useSessionCreate(campaignId);
  // Stays set until the session page is open, so the list never shows between create and navigate.
  const [busy, setBusy] = useState(false);

  async function createAndOpen() {
    setBusy(true);
    try {
      const session = await create.mutateAsync();
      await navigate({
        to: "/campaigns/$campaignId/sessions/$sessionId",
        params: { campaignId, sessionId: session.id },
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
        id="session-new"
        isLoading={busy}
        disabled={busy}
        onClick={() => void createAndOpen()}
      >
        <PlusIcon aria-hidden="true" data-icon="inline-start" />
        {children}
      </Button>
      {create.error && (
        <Alert id="session-error" variant="destructive">
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
