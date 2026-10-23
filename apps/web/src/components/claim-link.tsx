import { useState } from "react";
import { CheckIcon, CopyIcon } from "lucide-react";

import { Input } from "./ui/input";
import { Button } from "./ui/button";

/** GM only: the single-use link that lets the player claim an unclaimed character. */
export function ClaimLink({
  claimPath,
  playerName,
}: {
  claimPath: string;
  playerName: string | null;
}) {
  const [copied, setCopied] = useState(false);
  const url = `${window.location.origin}${claimPath}`;

  return (
    <div id="claim-link" className="space-y-2 rounded-xl border bg-card p-4">
      <p className="text-sm font-medium">
        {playerName ?? "The player"} has not claimed this character
      </p>
      <p className="text-sm text-muted-foreground">
        Send them this link. They sign up or sign in, then claim the character.
        It works once. Until then you manage the character.
      </p>
      <div className="flex gap-2">
        <Input
          id="claim-link-url"
          readOnly
          aria-label="Claim link"
          value={url}
          onFocus={event => event.target.select()}
        />
        <Button
          id="claim-link-copy"
          variant="outline"
          onClick={async () => {
            await navigator.clipboard.writeText(url);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          }}
        >
          {copied ? (
            <CheckIcon aria-hidden="true" data-icon="inline-start" />
          ) : (
            <CopyIcon aria-hidden="true" data-icon="inline-start" />
          )}
          {copied ? "Copied" : "Copy"}
        </Button>
      </div>
    </div>
  );
}
