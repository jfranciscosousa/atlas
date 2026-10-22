import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery } from "@tanstack/react-query";

import { rpcOptions } from "../lib/rpc";
import { mcpClientQueryOptions } from "../hooks/use-mcp";
import { Button } from "../components/ui/button";
import { Alert, AlertDescription } from "../components/ui/alert";

export const Route = createFileRoute("/_authenticated/connect")({
  validateSearch: (search: Record<string, unknown>) => ({
    client_id: String(search.client_id ?? ""),
  }),
  component: Connect,
});

// The OAuth parameters go back to the server as they came. The router would parse a value such
// as `state=123` into a number.
function oauthParams() {
  return Object.fromEntries(new URLSearchParams(window.location.search));
}

function Connect() {
  const { client_id } = Route.useSearch();
  const client = useQuery(mcpClientQueryOptions(client_id));
  const decide = useMutation({
    mutationFn: async (decision: "approve" | "deny", { meta }) => {
      const { headers, fetchOptions } = rpcOptions(meta);
      const response = await fetch("/oauth/authorize", {
        ...fetchOptions,
        method: "POST",
        headers: {
          ...headers,
          accept: "application/json",
          "content-type": "application/json",
        },
        body: JSON.stringify({ ...oauthParams(), decision }),
      });
      const data = await response.json();
      if (!response.ok)
        throw new Error(
          data.error_description ?? data.error ?? "Could not finish."
        );
      return data.redirect_to as string;
    },
    // The server checked the address against the URIs that the app registered.
    onSuccess: url => window.location.assign(url),
  });
  const error = client.error ?? decide.error;

  return (
    <section
      id="connect-page"
      className="mx-auto flex min-h-[50vh] max-w-md flex-col items-center justify-center gap-4 text-center"
    >
      <h1 className="text-3xl font-semibold">
        Connect {client.data?.name ?? "an app"} to Atlas?
      </h1>
      <p className="text-sm text-muted-foreground">
        The app will act as you in Atlas. It will read your campaigns, sessions,
        characters and notes, including GM-only text, and it will write where
        you can write: it creates sessions and notes, edits text and uploads
        images. It deletes nothing. You can revoke the access in Settings.
      </p>
      {error && (
        <Alert id="connect-error" variant="destructive">
          <AlertDescription>{error.message}</AlertDescription>
        </Alert>
      )}
      <div className="flex gap-2">
        <Button
          id="connect-deny"
          variant="outline"
          disabled={!client.data || decide.isPending || decide.isSuccess}
          onClick={() => decide.mutate("deny")}
        >
          Cancel
        </Button>
        <Button
          id="connect-approve"
          disabled={!client.data || decide.isSuccess}
          isLoading={decide.isPending}
          onClick={() => decide.mutate("approve")}
        >
          Allow
        </Button>
      </div>
    </section>
  );
}
