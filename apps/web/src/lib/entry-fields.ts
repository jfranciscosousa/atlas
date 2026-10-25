import type { EntryKind } from "./entry-kinds.ts";

// Custom fields: fields the GM defines for one kind of entry in one campaign. The API returns
// the values of an entry as an untyped list (`customValues`); this is its shape.

export const FIELD_TYPES = [
  "text",
  "number",
  "boolean",
  "select",
  "entry",
] as const;
export type FieldType = (typeof FIELD_TYPES)[number];

export const FIELD_TYPE_LABELS: Record<FieldType, string> = {
  text: "Text",
  number: "Number",
  boolean: "Yes / no",
  select: "Choice",
  entry: "Link to an entry",
};

/** The value of an entry field. A reader who cannot read the entry gets `restricted`, no ID. */
export type EntryRef = {
  kind: EntryKind;
  id: string | null;
  label: string;
  restricted: boolean;
  /** True when players read the entry. The preview restricts an entry that is not shown. */
  shown: boolean;
};

export type CustomValue = {
  id: string;
  label: string;
  type: FieldType;
  gm_only: boolean;
  position: number;
  choices: string[] | null;
  target_kind: EntryKind | null;
  value: string | number | boolean | EntryRef | null;
};

export const RESTRICTED_LABEL = "Restricted entry";

/**
 * The values as a player reads them. A player already gets only these. The preview gets the
 * GM's list and must cut it down: no GM-only field, and "Restricted entry" for an entry that is
 * not shown.
 */
export function playerValues(values: CustomValue[]): CustomValue[] {
  return values
    .filter(value => !value.gm_only)
    .map(value => {
      const ref = value.value;
      if (value.type === "entry" && isEntryRef(ref) && !ref.shown) {
        return {
          ...value,
          value: {
            ...ref,
            id: null,
            label: RESTRICTED_LABEL,
            restricted: true,
          },
        };
      }
      return value;
    });
}

export function isEntryRef(value: CustomValue["value"]): value is EntryRef {
  return typeof value === "object" && value !== null;
}

/** A value as the read-only page shows it, or `null` when there is nothing to show. */
export function valueText(value: CustomValue): string | null {
  const stored = value.value;
  if (stored === null || stored === undefined) return null;
  if (isEntryRef(stored)) return stored.label;
  if (typeof stored === "boolean") return stored ? "Yes" : "No";
  return String(stored);
}

/**
 * The write for a field that the GM edited. An empty input clears the field (`null`). A number
 * that is not a number is `undefined`: the caller shows nothing and keeps the saved value.
 */
export function inputToValue(
  type: FieldType,
  input: string
): string | number | boolean | null | undefined {
  const text = input.trim();
  if (text === "") return null;
  switch (type) {
    case "number": {
      const number = Number(text);
      return Number.isFinite(number) ? number : undefined;
    }
    case "boolean":
      return text === "true";
    default:
      return text;
  }
}

/** The input text of a saved value. */
export function valueToInput(value: CustomValue): string {
  const stored = value.value;
  if (stored === null || stored === undefined) return "";
  if (isEntryRef(stored)) return stored.id ?? "";
  return String(stored);
}

/** One choice in the editor: the saved name (`null` for a new one) and the text now in the input. */
export type ChoiceDraft = { original: string | null; text: string };

/**
 * The update that the choice editor makes. `choices` is the whole new list. `renamedChoices` maps
 * a saved choice whose text changed to its new text, so the stored values follow the rename.
 */
export function choiceUpdate(drafts: ChoiceDraft[]) {
  const kept = drafts
    .map(draft => ({ ...draft, text: draft.text.trim() }))
    .filter(draft => draft.text !== "");
  const renamedChoices: Record<string, string> = {};
  for (const draft of kept) {
    if (draft.original !== null && draft.original !== draft.text) {
      renamedChoices[draft.original] = draft.text;
    }
  }
  return {
    choices: kept.map(draft => draft.text),
    ...(Object.keys(renamedChoices).length > 0 && { renamedChoices }),
  };
}
