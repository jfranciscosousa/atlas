import { useState } from "react";
import { FilterIcon, XIcon } from "lucide-react";
import { useQuery } from "@tanstack/react-query";

import { Skeleton } from "./ui/skeleton";
import { NativeSelect } from "./ui/native-select";
import { Label } from "./ui/label";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
import { ENTRY_KIND_LABELS, type EntryKind } from "../lib/entry-kinds";
import {
  entryFieldsQueryOptions,
  fieldChoices,
  fieldTargetKind,
  type EntryFieldRecord,
} from "../hooks/use-entry-fields";
import { useEntriesList } from "../hooks/use-entries";

// Every state of the bar keeps this height, so the list below never jumps.
const BAR_HEIGHT = "min-h-[5.125rem]";

/**
 * Keeps the entries of one kind whose custom field has one value (equality). The value is text,
 * as the API reads it: a number as "3", a boolean as "true", a choice as its name, an entry as
 * its ID. The choice of field and value is in the URL, so a filtered list can be shared.
 */
export function EntryFieldFilter({
  campaignId,
  kind,
  fieldId,
  value,
  isGm,
  onChange,
}: {
  campaignId: string;
  kind: EntryKind;
  fieldId?: string;
  value?: string;
  isGm: boolean | null;
  onChange: (filter: { field?: string; value?: string }) => void;
}) {
  // Every kind of this campaign in one read: a kind switch must not empty the bar.
  const fields = useQuery(entryFieldsQueryOptions(campaignId));
  if (fields.isPending) return <LoadingFilter />;
  if (fields.error) {
    return (
      <FilterNotice>
        <p className="text-sm text-destructive">{fields.error.message}</p>
      </FilterNotice>
    );
  }
  const kindFields = (fields.data ?? []).filter(
    candidate => candidate.kind === kind
  );
  if (kindFields.length === 0) {
    return (
      <FilterNotice>
        <FilterIcon
          aria-hidden="true"
          className="size-4 shrink-0 text-muted-foreground"
        />
        <div className="min-w-0">
          <p className="text-sm font-medium">
            No custom fields for {ENTRY_KIND_LABELS[kind].plural.toLowerCase()}{" "}
            yet
          </p>
          <p className="text-sm text-muted-foreground">
            {isGm
              ? "Custom fields are details you add to a kind. Add one with Fields to filter this list."
              : "Custom fields are details the GM adds to a kind. They become filters here."}
          </p>
        </div>
      </FilterNotice>
    );
  }
  const field = kindFields.find(candidate => candidate.id === fieldId);

  return (
    <div
      id="entry-field-filter"
      className={`flex flex-wrap items-end gap-3 rounded-2xl border bg-card p-3 ${BAR_HEIGHT}`}
    >
      <div className="grid gap-1.5">
        <Label htmlFor="entry-filter-field">Filter by field</Label>
        <NativeSelect
          id="entry-filter-field"
          className="min-w-44"
          value={field?.id ?? ""}
          onChange={event =>
            onChange(event.target.value ? { field: event.target.value } : {})
          }
        >
          <option value="">No filter</option>
          {kindFields.map(candidate => (
            <option key={candidate.id} value={candidate.id}>
              {candidate.label}
            </option>
          ))}
        </NativeSelect>
      </div>
      {field && (
        <div className="grid gap-1.5">
          <Label htmlFor="entry-filter-value">Equals</Label>
          <ValueControl
            // A new field starts with a new value input.
            key={field.id}
            campaignId={campaignId}
            field={field}
            value={value ?? ""}
            onChange={next => onChange({ field: field.id, value: next })}
          />
        </div>
      )}
      {field && (
        <Button
          id="entry-filter-clear"
          variant="ghost"
          size="sm"
          onClick={() => onChange({})}
        >
          <XIcon aria-hidden="true" data-icon="inline-start" />
          Clear
        </Button>
      )}
      {!field && (
        <FilterIcon
          aria-hidden="true"
          className="mb-2 size-4 text-muted-foreground"
        />
      )}
    </div>
  );
}

/**
 * The same bar with the same height while the fields load, so the list below does not jump.
 */
function LoadingFilter() {
  return (
    <div
      id="entry-field-filter"
      role="status"
      aria-label="Loading the filter"
      className={`flex flex-wrap items-end gap-3 rounded-2xl border bg-card p-3 ${BAR_HEIGHT}`}
    >
      <div className="grid gap-1.5">
        <Skeleton className="h-3.5 w-20 rounded-md" />
        <Skeleton className="h-9 w-44 rounded-lg" />
      </div>
    </div>
  );
}

/** A quiet bar in place of the filter, with the same height. */
function FilterNotice({ children }: { children: React.ReactNode }) {
  return (
    <div
      id="entry-field-filter"
      className={`flex flex-wrap items-center gap-3 rounded-2xl border border-dashed bg-card/50 p-3 ${BAR_HEIGHT}`}
    >
      {children}
    </div>
  );
}

function ValueControl({
  campaignId,
  field,
  value,
  onChange,
}: {
  campaignId: string;
  field: EntryFieldRecord;
  value: string;
  onChange: (value: string | undefined) => void;
}) {
  const [text, setText] = useState(value);
  const target = fieldTargetKind(field);
  const entries = useEntriesList(campaignId).data.filter(
    entry => entry.kind === target
  );

  switch (field.type) {
    case "text":
    case "number":
      return (
        <Input
          id="entry-filter-value"
          type={field.type}
          step={field.type === "number" ? "any" : undefined}
          className="min-w-44"
          value={text}
          onChange={event => setText(event.target.value)}
          onBlur={() => onChange(text.trim() || undefined)}
          onKeyDown={event =>
            event.key === "Enter" && event.currentTarget.blur()
          }
        />
      );
    case "boolean":
      return (
        <Select value={value} onChange={onChange}>
          <option value="true">Yes</option>
          <option value="false">No</option>
        </Select>
      );
    case "select":
      return (
        <Select value={value} onChange={onChange}>
          {fieldChoices(field).map(choice => (
            <option key={choice} value={choice}>
              {choice}
            </option>
          ))}
        </Select>
      );
    case "entry":
      return (
        <Select value={value} onChange={onChange}>
          {entries.map(entry => (
            <option key={entry.id} value={entry.id}>
              {entry.name}
            </option>
          ))}
        </Select>
      );
  }
}

function Select({
  value,
  onChange,
  children,
}: {
  value: string;
  onChange: (value: string | undefined) => void;
  children: React.ReactNode;
}) {
  return (
    <NativeSelect
      id="entry-filter-value"
      className="min-w-44"
      value={value}
      onChange={event => onChange(event.target.value || undefined)}
    >
      <option value="">Choose a value</option>
      {children}
    </NativeSelect>
  );
}
