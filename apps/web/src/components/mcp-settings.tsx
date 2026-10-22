import { useState } from "react";
import { CheckIcon, CopyIcon } from "lucide-react";

import { Input } from "./ui/input";
import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { useMcpConnectionRevoke, useMcpConnections } from "../hooks/use-mcp";

function formatDate(value: string | null) {
  return value ? new Date(value).toLocaleDateString() : "never";
}

export function McpSettings({ userId }: { userId: string }) {
  const connections = useMcpConnections(userId).data;
  const revoke = useMcpConnectionRevoke(userId);
  const [copied, setCopied] = useState(false);
  const url = `${window.location.origin}/mcp`;

  return (
    <section id="mcp-settings" className="space-y-6">
      <div className="space-y-1">
        <h2 className="text-lg font-semibold">MCP server</h2>
        <p className="text-sm text-muted-foreground">
          Add this URL as a remote MCP server in Claude, ChatGPT, opencode or
          pi. Atlas asks you to sign in and allow the app. The app acts as you:
          it reads your campaigns, sessions, characters and notes, including
          GM-only text, and it writes where you can write. It creates sessions
          and notes, edits text and uploads images. It deletes nothing.
        </p>
      </div>
      <div className="flex gap-2">
        <Input
          id="mcp-url"
          readOnly
          aria-label="MCP server URL"
          value={url}
          onFocus={event => event.target.select()}
        />
        <Button
          id="mcp-copy"
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

      <div className="space-y-3">
        <h3 className="text-sm font-medium">Connected apps</h3>
        {revoke.error && (
          <Alert variant="destructive">
            <AlertDescription>{revoke.error.message}</AlertDescription>
          </Alert>
        )}
        <ul id="mcp-connections" className="divide-y rounded-xl border bg-card">
          {connections.map(connection => (
            <li
              key={connection.id}
              className="flex items-center justify-between gap-3 px-4 py-3 text-sm"
            >
              <span className="min-w-0">
                <span className="block truncate font-medium">
                  {connection.clientName}
                </span>
                <span className="text-muted-foreground">
                  Connected {formatDate(connection.insertedAt)} · last used{" "}
                  {formatDate(connection.lastUsedAt)}
                </span>
              </span>
              <Button
                variant="outline"
                size="sm"
                isLoading={
                  revoke.isPending && revoke.variables === connection.id
                }
                onClick={() => revoke.mutate(connection.id)}
              >
                Revoke
              </Button>
            </li>
          ))}
          {connections.length === 0 && (
            <li
              id="mcp-empty"
              className="px-4 py-3 text-sm text-muted-foreground"
            >
              No app is connected yet.
            </li>
          )}
        </ul>
      </div>
    </section>
  );
}
