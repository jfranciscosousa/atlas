import { Link } from "@tanstack/react-router";

import { ENTRY_ICONS } from "./entry-icons";
import { ENTRY_KIND_LABELS, ENTRY_KINDS } from "../lib/entry-kinds";
import { useEntriesList } from "../hooks/use-entries";

/** The world entries that players read, as the preview shows them. Hidden entries are absent. */
export function PreviewWorld({ campaignId }: { campaignId: string }) {
  const entries = useEntriesList(campaignId, { asPlayer: true }).data;

  return (
    <section id="preview-world" className="space-y-3">
      <h2 className="font-heading text-xl font-semibold">World</h2>
      {entries.length === 0 ? (
        <p id="preview-world-empty" className="text-sm text-muted-foreground">
          You have not shown any entry to the players yet.
        </p>
      ) : (
        ENTRY_KINDS.map(kind => {
          const ofKind = entries.filter(entry => entry.kind === kind);
          if (ofKind.length === 0) return null;
          const Icon = ENTRY_ICONS[kind];
          return (
            <div key={kind} className="space-y-2">
              <h3 className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
                <Icon aria-hidden="true" className="size-4" />
                {ENTRY_KIND_LABELS[kind].plural}
              </h3>
              <ul className="grid gap-2">
                {ofKind.map(entry => (
                  <li key={entry.id}>
                    <Link
                      id={`preview-entry-${entry.id}`}
                      to="/campaigns/$campaignId/preview/entries/$entryId"
                      params={{ campaignId, entryId: entry.id }}
                      className="flex items-center gap-3 rounded-2xl border bg-card px-4 py-3 shadow-xs outline-none focus-visible:ring-3 focus-visible:ring-ring/30"
                    >
                      <span className="min-w-0 flex-1 truncate font-medium">
                        {entry.name}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          );
        })
      )}
    </section>
  );
}
