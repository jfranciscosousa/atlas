import type { ComponentType } from "react";

import { CalendarPlusIcon, PencilLineIcon, ScrollTextIcon } from "lucide-react";
import { cn } from "cn";

import type { EntrySort } from "../lib/entry-sort";

import { formatExactly, formatWhen } from "../lib/entry-dates";

type EntryMetaProps = {
  editedAt?: string;
  insertedAt?: string;
  /** The latest session whose log mentions the entry. Null when none does. */
  lastSessionNumber?: number | null;
  /** The chip of the active sort stands out. */
  sort: EntrySort;
};

function Chip({
  icon: Icon,
  active,
  title,
  children,
}: {
  icon: ComponentType<{ "aria-hidden"?: boolean; className?: string }>;
  active: boolean;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <span
      title={title}
      className={cn(
        "inline-flex items-center gap-1",
        active && "font-medium text-foreground"
      )}
    >
      <Icon aria-hidden={true} className="size-3.5 shrink-0" />
      {children}
    </span>
  );
}

/**
 * When the entry was edited and created, and the latest session that mentions it. The chip of
 * the active sort stands out, so the order explains itself.
 */
export function EntryMeta({
  editedAt,
  insertedAt,
  lastSessionNumber,
  sort,
}: EntryMetaProps) {
  if (!editedAt || !insertedAt) return null;
  const now = Date.now();
  const mentioned = lastSessionNumber != null;

  return (
    <span className="flex flex-wrap items-center gap-x-4 gap-y-0.5 text-xs text-muted-foreground">
      <Chip
        icon={PencilLineIcon}
        active={sort === "last_edited"}
        title={`Last edit: ${formatExactly(editedAt)}`}
      >
        <time dateTime={editedAt}>Edited {formatWhen(editedAt, now)}</time>
      </Chip>
      <Chip
        icon={CalendarPlusIcon}
        active={sort === "last_created"}
        title={`Created: ${formatExactly(insertedAt)}`}
      >
        <time dateTime={insertedAt}>Created {formatWhen(insertedAt, now)}</time>
      </Chip>
      {(mentioned || sort === "last_mentioned") && (
        <Chip
          icon={ScrollTextIcon}
          active={sort === "last_mentioned"}
          title="The latest session log that mentions this entry"
        >
          {mentioned ? `In session ${lastSessionNumber}` : "In no session log"}
        </Chip>
      )}
    </span>
  );
}
