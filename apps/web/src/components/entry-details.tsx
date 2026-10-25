import { useState } from "react";
import { Link } from "@tanstack/react-router";

import { NativeSelect } from "./ui/native-select";
import { Label } from "./ui/label";
import { Input } from "./ui/input";
import { Alert, AlertDescription } from "./ui/alert";
import { EntryImage } from "./entry-image";
import { CustomFieldInputs } from "./entry-custom-fields";
import { EntryStatusBadge } from "./entry-badges";
import { endPath, statusLabel } from "../lib/entry-kinds";
import {
  isEntryRef,
  playerValues,
  valueText,
  type CustomValue,
} from "../lib/entry-fields";
import {
  useEntriesList,
  useEntryKinds,
  useEntryUpdate,
  type useEntry,
} from "../hooks/use-entries";

type Entry = ReturnType<typeof useEntry>["data"];

/**
 * The status, the built-in fields, the parent location and the image of an entry. The GM edits
 * them in place. Everyone else, and the preview, reads them.
 */
export function EntryDetails({
  campaignId,
  entry,
  canManage,
  preview = false,
}: {
  campaignId: string;
  entry: Entry;
  canManage: boolean;
  preview?: boolean;
}) {
  const spec = useEntryKinds().kinds.find(kind => kind.kind === entry.kind);
  const update = useEntryUpdate(campaignId, entry.id);
  const fields = spec?.fields ?? [];
  const hasImage = Boolean(entry.imageId);
  // The GM sees every custom field. A player's list is already cut down. The preview cuts the
  // GM's list down the same way.
  const customValues = (entry.customValues ?? []) as CustomValue[];
  const readable = preview ? playerValues(customValues) : customValues;
  // A player gets the parent only when players read it too. The preview must do the same.
  const parent =
    entry.parentId && entry.parentName && entry.parentShown !== false
      ? { id: entry.parentId, name: entry.parentName }
      : undefined;

  return (
    <section
      id="entry-details"
      aria-label="Details"
      className={
        hasImage ? "grid gap-6 md:grid-cols-[14rem_1fr]" : "grid gap-6"
      }
    >
      {(entry.imageId || canManage) && (
        <EntryImage
          imageId={entry.imageId}
          name={entry.name}
          canManage={canManage}
          disabled={update.isPending}
          onChange={imageId => update.mutate({ imageId })}
        />
      )}
      <div className={hasImage ? "space-y-4 md:col-start-2" : "space-y-4"}>
        {canManage ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label htmlFor="entry-status">Status</Label>
              <NativeSelect
                id="entry-status"
                value={entry.status}
                disabled={update.isPending}
                onChange={event =>
                  update.mutate({
                    status: event.target.value as typeof entry.status,
                  })
                }
              >
                {spec?.statuses.map(status => (
                  <option key={status} value={status}>
                    {statusLabel(status)}
                  </option>
                ))}
              </NativeSelect>
            </div>
            {fields.map(field => (
              <FieldInput
                key={`${entry.id}-${field.key}`}
                id={`entry-field-${field.key}`}
                label={field.label}
                maxLength={field.max_length}
                saved={entry.fields[field.key] ?? ""}
                disabled={update.isPending}
                onCommit={value =>
                  update.mutate({ fields: { [field.key]: value } })
                }
              />
            ))}
            <CustomFieldInputs
              campaignId={campaignId}
              entryId={entry.id}
              values={customValues}
              disabled={update.isPending}
              onChange={(fieldId, value) =>
                update.mutate({ customValues: { [fieldId]: value } })
              }
            />
            {entry.kind === "location" && (
              <ParentSelect
                campaignId={campaignId}
                entryId={entry.id}
                parentId={entry.parentId}
                disabled={update.isPending}
                onChange={parentId => update.mutate({ parentId })}
              />
            )}
          </div>
        ) : (
          <dl className="grid gap-x-8 gap-y-3 sm:grid-cols-2">
            <Item label="Status">
              <EntryStatusBadge status={entry.status} />
            </Item>
            {fields.map(field => {
              const value = entry.fields[field.key];
              return value ? (
                <Item
                  key={field.key}
                  label={field.label}
                  id={`entry-field-${field.key}`}
                >
                  {value}
                </Item>
              ) : null;
            })}
            {readable.map(value => {
              const text = valueText(value);
              if (text === null) return null;
              const target = isEntryRef(value.value) ? value.value : null;
              return (
                <Item
                  key={value.id}
                  label={value.label}
                  id={`entry-custom-${value.id}`}
                >
                  {target?.id ? (
                    <Link
                      to={endPath(campaignId, target.kind, target.id, preview)}
                      className="font-medium text-primary underline-offset-4 hover:underline"
                    >
                      {text}
                    </Link>
                  ) : (
                    text
                  )}
                </Item>
              );
            })}
            {parent && (
              <Item label="Inside" id="entry-parent">
                <Link
                  to={endPath(campaignId, "location", parent.id, preview)}
                  className="font-medium text-primary underline-offset-4 hover:underline"
                >
                  {parent.name}
                </Link>
              </Item>
            )}
          </dl>
        )}
        {update.error && (
          <Alert id="entry-update-error" variant="destructive">
            <AlertDescription>{update.error.message}</AlertDescription>
          </Alert>
        )}
      </div>
    </section>
  );
}

function Item({
  label,
  id,
  children,
}: {
  label: string;
  id?: string;
  children: React.ReactNode;
}) {
  return (
    <div id={id} className="space-y-0.5">
      <dt className="text-xs font-medium tracking-wide text-muted-foreground uppercase">
        {label}
      </dt>
      <dd className="text-sm">{children}</dd>
    </div>
  );
}

// The field keeps its own text while typing and saves when it loses focus.
function FieldInput({
  id,
  label,
  maxLength,
  saved,
  disabled,
  onCommit,
}: {
  id: string;
  label: string;
  maxLength: number;
  saved: string;
  disabled: boolean;
  onCommit: (value: string) => void;
}) {
  const [value, setValue] = useState(saved);
  return (
    <div className="grid gap-2">
      <Label htmlFor={id}>{label}</Label>
      <Input
        id={id}
        maxLength={maxLength}
        value={value}
        disabled={disabled}
        onChange={event => setValue(event.target.value)}
        onBlur={() => {
          const next = value.trim();
          setValue(next);
          if (next !== saved) onCommit(next);
        }}
        onKeyDown={event => event.key === "Enter" && event.currentTarget.blur()}
      />
    </div>
  );
}

function ParentSelect({
  campaignId,
  entryId,
  parentId,
  disabled,
  onChange,
}: {
  campaignId: string;
  entryId: string;
  parentId: string | null;
  disabled: boolean;
  onChange: (parentId: string | null) => void;
}) {
  const locations = useEntriesList(campaignId).data.filter(
    entry => entry.kind === "location" && entry.id !== entryId
  );
  return (
    <div className="grid gap-2">
      <Label htmlFor="entry-parent-select">Inside</Label>
      <NativeSelect
        id="entry-parent-select"
        value={parentId ?? ""}
        disabled={disabled}
        onChange={event => onChange(event.target.value || null)}
      >
        <option value="">Nowhere in particular</option>
        {locations.map(location => (
          <option key={location.id} value={location.id}>
            {location.name}
          </option>
        ))}
      </NativeSelect>
    </div>
  );
}
