import { useState } from "react";
import { LockIcon } from "lucide-react";

import { NativeSelect } from "./ui/native-select";
import { Label } from "./ui/label";
import { Input } from "./ui/input";
import {
  inputToValue,
  isEntryRef,
  valueToInput,
  type CustomValue,
} from "../lib/entry-fields";
import { useEntriesList } from "../hooks/use-entries";

/**
 * The GM's inputs for the custom fields of an entry, one for each field in order. A change
 * saves at once: text and number when the input loses focus, the others when the choice is made.
 */
export function CustomFieldInputs({
  campaignId,
  entryId,
  values,
  disabled,
  onChange,
}: {
  campaignId: string;
  entryId: string;
  values: CustomValue[];
  disabled: boolean;
  onChange: (fieldId: string, value: string | number | boolean | null) => void;
}) {
  return (
    <>
      {values.map(value => (
        <div key={`${entryId}-${value.id}`} className="grid gap-2">
          <Label htmlFor={`entry-custom-${value.id}`}>
            {value.label}
            {value.gm_only && (
              <span
                className="inline-flex items-center gap-1 text-xs font-normal text-muted-foreground"
                title="Only you, the GM, see this field. Players never receive it."
              >
                <LockIcon aria-hidden="true" className="size-3" />
                GM only
              </span>
            )}
          </Label>
          <CustomFieldInput
            campaignId={campaignId}
            entryId={entryId}
            value={value}
            disabled={disabled}
            onChange={next => onChange(value.id, next)}
          />
        </div>
      ))}
    </>
  );
}

function CustomFieldInput({
  campaignId,
  entryId,
  value,
  disabled,
  onChange,
}: {
  campaignId: string;
  entryId: string;
  value: CustomValue;
  disabled: boolean;
  onChange: (value: string | number | boolean | null) => void;
}) {
  const id = `entry-custom-${value.id}`;
  const saved = valueToInput(value);

  switch (value.type) {
    case "text":
    case "number":
      return (
        <TypedInput
          id={id}
          type={value.type}
          saved={saved}
          disabled={disabled}
          onCommit={onChange}
        />
      );
    case "boolean":
      return (
        <NativeSelect
          id={id}
          value={saved}
          disabled={disabled}
          onChange={event =>
            onChange(inputToValue("boolean", event.target.value) ?? null)
          }
        >
          <option value="">Not set</option>
          <option value="true">Yes</option>
          <option value="false">No</option>
        </NativeSelect>
      );
    case "select":
      return (
        <NativeSelect
          id={id}
          value={saved}
          disabled={disabled}
          onChange={event => onChange(event.target.value || null)}
        >
          <option value="">Not set</option>
          {value.choices?.map(choice => (
            <option key={choice} value={choice}>
              {choice}
            </option>
          ))}
        </NativeSelect>
      );
    case "entry":
      return (
        <EntryChoice
          id={id}
          campaignId={campaignId}
          entryId={entryId}
          value={value}
          disabled={disabled}
          onChange={onChange}
        />
      );
  }
}

// Keeps its own text while typing and saves when it loses focus.
function TypedInput({
  id,
  type,
  saved,
  disabled,
  onCommit,
}: {
  id: string;
  type: "text" | "number";
  saved: string;
  disabled: boolean;
  onCommit: (value: string | number | null) => void;
}) {
  const [text, setText] = useState(saved);
  return (
    <Input
      id={id}
      type={type}
      step={type === "number" ? "any" : undefined}
      maxLength={type === "text" ? 500 : undefined}
      value={text}
      disabled={disabled}
      onChange={event => setText(event.target.value)}
      onBlur={() => {
        const next = inputToValue(type, text);
        if (next === undefined) return setText(saved);
        const nextText = next === null ? "" : String(next);
        setText(nextText);
        if (nextText !== saved) onCommit(next as string | number | null);
      }}
      onKeyDown={event => event.key === "Enter" && event.currentTarget.blur()}
    />
  );
}

// The entries of the target kind. The saved entry stays in the list when it is archived.
function EntryChoice({
  id,
  campaignId,
  entryId,
  value,
  disabled,
  onChange,
}: {
  id: string;
  campaignId: string;
  entryId: string;
  value: CustomValue;
  disabled: boolean;
  onChange: (value: string | null) => void;
}) {
  const entries = useEntriesList(campaignId).data.filter(
    entry => entry.kind === value.target_kind && entry.id !== entryId
  );
  const saved = isEntryRef(value.value) ? value.value : null;
  const listed = saved && entries.some(entry => entry.id === saved.id);
  return (
    <NativeSelect
      id={id}
      value={saved?.id ?? ""}
      disabled={disabled}
      onChange={event => onChange(event.target.value || null)}
    >
      <option value="">Nothing</option>
      {saved?.id && !listed && <option value={saved.id}>{saved.label}</option>}
      {entries.map(entry => (
        <option key={entry.id} value={entry.id}>
          {entry.name}
        </option>
      ))}
    </NativeSelect>
  );
}
