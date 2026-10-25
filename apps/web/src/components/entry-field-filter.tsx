import { useState } from "react";
import { FilterIcon, XIcon } from "lucide-react";
import { useQuery } from "@tanstack/react-query";

import type { EntryKind } from "../lib/entry-kinds";

import { NativeSelect } from "./ui/native-select";
import { Label } from "./ui/label";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
import {
  entryFieldsQueryOptions,
  fieldChoices,
  fieldTargetKind,
  type EntryFieldRecord,
} from "../hooks/use-entry-fields";
import { useEntriesList } from "../hooks/use-entries";

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
  onChange,
}: {
  campaignId: string;
  kind: EntryKind;
  fieldId?: string;
  value?: string;
  onChange: (filter: { field?: string; value?: string }) => void;
}) {
  const fields = useQuery(entryFieldsQueryOptions(campaignId, { kind })).data;
  const field = fields?.find(candidate => candidate.id === fieldId);
  if (!fields || fields.length === 0) return null;

  return (
    <div
      id="entry-field-filter"
      className="flex flex-wrap items-end gap-3 rounded-2xl border bg-card p-3"
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
          {fields.map(candidate => (
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
