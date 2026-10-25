import { useState } from "react";
import {
  ArchiveIcon,
  ArchiveRestoreIcon,
  ArrowDownIcon,
  ArrowUpIcon,
  LockIcon,
  PlusIcon,
  SlidersHorizontalIcon,
  XIcon,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";

import { NativeSelect } from "./ui/native-select";
import { Label } from "./ui/label";
import { Input } from "./ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "./ui/dialog";
import { Checkbox } from "./ui/checkbox";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { Alert, AlertDescription } from "./ui/alert";
import {
  ENTRY_KIND_LABELS,
  ENTRY_KINDS,
  type EntryKind,
} from "../lib/entry-kinds";
import {
  FIELD_TYPE_LABELS,
  FIELD_TYPES,
  choiceUpdate,
  type ChoiceDraft,
  type FieldType,
} from "../lib/entry-fields";
import {
  entryFieldsQueryOptions,
  fieldChoices,
  fieldTargetKind,
  useEntryFieldArchive,
  useEntryFieldCreate,
  useEntryFieldMove,
  useEntryFieldRestore,
  useEntryFieldUpdate,
  type EntryFieldRecord,
} from "../hooks/use-entry-fields";

/**
 * The GM defines the custom fields of each kind here: fields for this campaign only. The button
 * opens a dialog. Only the GM sees it.
 */
export function EntryFieldsManager({
  campaignId,
  kind,
}: {
  campaignId: string;
  /** The kind the dialog starts with. */
  kind?: EntryKind;
}) {
  return (
    <Dialog>
      <DialogTrigger
        render={
          <Button id="entry-fields-open" variant="outline">
            <SlidersHorizontalIcon
              aria-hidden="true"
              data-icon="inline-start"
            />
            Fields
          </Button>
        }
      />
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>Custom fields</DialogTitle>
          <DialogDescription>
            Fields you add to one kind of entry in this campaign. Players see a
            field and its values, unless you make it GM only. A field is
            archived, never deleted.
          </DialogDescription>
        </DialogHeader>
        <FieldsBody campaignId={campaignId} initialKind={kind ?? "npc"} />
      </DialogContent>
    </Dialog>
  );
}

function FieldsBody({
  campaignId,
  initialKind,
}: {
  campaignId: string;
  initialKind: EntryKind;
}) {
  const [kind, setKind] = useState<EntryKind>(initialKind);
  const active = useQuery(entryFieldsQueryOptions(campaignId, { kind }));
  const archived = useQuery(
    entryFieldsQueryOptions(campaignId, { kind, archived: true })
  );
  const archive = useEntryFieldArchive(campaignId);
  const restore = useEntryFieldRestore(campaignId);
  const move = useEntryFieldMove(campaignId);
  const error = archive.error ?? restore.error ?? move.error;
  const fields = active.data ?? [];

  return (
    <div className="space-y-5">
      <div className="grid gap-2">
        <Label htmlFor="entry-fields-kind">Kind of entry</Label>
        <NativeSelect
          id="entry-fields-kind"
          value={kind}
          onChange={event => setKind(event.target.value as EntryKind)}
        >
          {ENTRY_KINDS.map(entryKind => (
            <option key={entryKind} value={entryKind}>
              {ENTRY_KIND_LABELS[entryKind].label}
            </option>
          ))}
        </NativeSelect>
      </div>
      {error && (
        <Alert id="entry-fields-error" variant="destructive">
          <AlertDescription>{error.message}</AlertDescription>
        </Alert>
      )}
      {fields.length === 0 ? (
        <p id="entry-fields-empty" className="text-sm text-muted-foreground">
          No custom fields for {ENTRY_KIND_LABELS[kind].plural.toLowerCase()}{" "}
          yet.
        </p>
      ) : (
        <ul id="entry-fields-list" className="space-y-3">
          {fields.map((field, index) => (
            <FieldRow
              key={field.id}
              campaignId={campaignId}
              field={field}
              first={index === 0}
              last={index === fields.length - 1}
              busy={move.isPending || archive.isPending}
              onMove={position => move.mutate({ id: field.id, position })}
              onArchive={() => archive.mutate(field.id)}
              index={index}
            />
          ))}
        </ul>
      )}
      <NewFieldForm campaignId={campaignId} kind={kind} />
      {(archived.data?.length ?? 0) > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-medium">Archived fields</h3>
          <p className="text-xs text-muted-foreground">
            Their values are hidden everywhere. Restore a field to show them
            again.
          </p>
          <ul id="entry-fields-archived" className="divide-y rounded-xl border">
            {archived.data?.map(field => (
              <li
                key={field.id}
                className="flex items-center justify-between gap-3 px-3 py-2 text-sm"
              >
                <span>{field.label}</span>
                <Button
                  id={`entry-field-restore-${field.id}`}
                  variant="ghost"
                  size="sm"
                  disabled={restore.isPending}
                  onClick={() => restore.mutate(field.id)}
                >
                  <ArchiveRestoreIcon
                    aria-hidden="true"
                    data-icon="inline-start"
                  />
                  Restore
                </Button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function FieldRow({
  campaignId,
  field,
  index,
  first,
  last,
  busy,
  onMove,
  onArchive,
}: {
  campaignId: string;
  field: EntryFieldRecord;
  index: number;
  first: boolean;
  last: boolean;
  busy: boolean;
  onMove: (position: number) => void;
  onArchive: () => void;
}) {
  const update = useEntryFieldUpdate(campaignId);
  const [label, setLabel] = useState(field.label);
  const target = fieldTargetKind(field);

  function commitLabel() {
    const next = label.trim();
    if (!next) return setLabel(field.label);
    if (next !== field.label) update.mutate({ id: field.id, label: next });
  }

  return (
    <li
      id={`entry-field-${field.id}`}
      className="space-y-3 rounded-xl border bg-card p-3"
    >
      <div className="flex flex-wrap items-center gap-2">
        <Input
          aria-label="Label"
          className="min-w-40 flex-1"
          maxLength={60}
          value={label}
          onChange={event => setLabel(event.target.value)}
          onBlur={commitLabel}
          onKeyDown={event =>
            event.key === "Enter" && event.currentTarget.blur()
          }
        />
        <Badge variant="outline">
          {FIELD_TYPE_LABELS[field.type]}
          {target && `: ${ENTRY_KIND_LABELS[target].label}`}
        </Badge>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Move ${field.label} up`}
          disabled={first || busy}
          onClick={() => onMove(index - 1)}
        >
          <ArrowUpIcon />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Move ${field.label} down`}
          disabled={last || busy}
          onClick={() => onMove(index + 1)}
        >
          <ArrowDownIcon />
        </Button>
        <Button
          id={`entry-field-archive-${field.id}`}
          variant="ghost"
          size="icon"
          aria-label={`Archive ${field.label}`}
          title="Archive"
          disabled={busy}
          onClick={onArchive}
        >
          <ArchiveIcon />
        </Button>
      </div>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox
          checked={field.gmOnly}
          disabled={update.isPending}
          onCheckedChange={checked =>
            update.mutate({ id: field.id, gmOnly: checked })
          }
        />
        <LockIcon aria-hidden="true" className="size-3.5" />
        GM only: players never see this field or its values
      </label>
      {field.type === "select" && (
        <ChoiceEditor
          campaignId={campaignId}
          field={field}
          choices={fieldChoices(field)}
        />
      )}
      {update.error && (
        <Alert variant="destructive">
          <AlertDescription>{update.error.message}</AlertDescription>
        </Alert>
      )}
    </li>
  );
}

// An edited choice keeps its saved name, so the stored values follow a rename.
function ChoiceEditor({
  campaignId,
  field,
  choices,
}: {
  campaignId: string;
  field: EntryFieldRecord;
  choices: string[];
}) {
  const update = useEntryFieldUpdate(campaignId);
  const initial = (): ChoiceDraft[] =>
    choices.map(choice => ({ original: choice, text: choice }));
  const [drafts, setDrafts] = useState<ChoiceDraft[]>(initial);
  const change = (index: number, patch: Partial<ChoiceDraft>) =>
    setDrafts(list =>
      list.map((draft, at) => (at === index ? { ...draft, ...patch } : draft))
    );

  return (
    <div className="space-y-2 border-t pt-3">
      <p className="text-xs font-medium text-muted-foreground">Choices</p>
      <ul className="space-y-2">
        {drafts.map((draft, index) => (
          <li key={index} className="flex items-center gap-2">
            <Input
              aria-label={`Choice ${index + 1}`}
              maxLength={60}
              value={draft.text}
              onChange={event => change(index, { text: event.target.value })}
            />
            <Button
              variant="ghost"
              size="icon"
              aria-label={`Remove choice ${index + 1}`}
              onClick={() => change(index, { text: "" })}
              disabled={draft.text === ""}
            >
              <XIcon />
            </Button>
          </li>
        ))}
      </ul>
      <div className="flex flex-wrap gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() =>
            setDrafts(list => [...list, { original: null, text: "" }])
          }
        >
          <PlusIcon aria-hidden="true" data-icon="inline-start" />
          Add a choice
        </Button>
        <Button
          id={`entry-field-choices-save-${field.id}`}
          size="sm"
          disabled={update.isPending}
          onClick={() =>
            update.mutate(
              { id: field.id, ...choiceUpdate(drafts) },
              {
                onSuccess: () =>
                  setDrafts(list =>
                    list
                      .filter(draft => draft.text.trim() !== "")
                      .map(draft => ({
                        original: draft.text.trim(),
                        text: draft.text.trim(),
                      }))
                  ),
              }
            )
          }
        >
          Save choices
        </Button>
      </div>
      {update.error && (
        <Alert id="entry-field-choices-error" variant="destructive">
          <AlertDescription>{update.error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}

function NewFieldForm({
  campaignId,
  kind,
}: {
  campaignId: string;
  kind: EntryKind;
}) {
  const create = useEntryFieldCreate(campaignId);
  const [label, setLabel] = useState("");
  const [type, setType] = useState<FieldType>("text");
  const [choices, setChoices] = useState("");
  const [target, setTarget] = useState<EntryKind>("location");
  const [gmOnly, setGmOnly] = useState(false);

  function submit(event: React.FormEvent) {
    event.preventDefault();
    create.mutate(
      {
        kind,
        label: label.trim(),
        type,
        gmOnly,
        ...(type === "select" && {
          choices: choices
            .split(",")
            .map(choice => choice.trim())
            .filter(Boolean),
        }),
        ...(type === "entry" && { targetKind: target }),
      },
      {
        onSuccess: () => {
          setLabel("");
          setChoices("");
          setGmOnly(false);
        },
      }
    );
  }

  return (
    <form
      id="entry-field-new"
      onSubmit={submit}
      className="space-y-3 rounded-xl border border-dashed p-3"
    >
      <h3 className="text-sm font-medium">Add a field</h3>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-2">
          <Label htmlFor="entry-field-new-label">Label</Label>
          <Input
            id="entry-field-new-label"
            maxLength={60}
            value={label}
            onChange={event => setLabel(event.target.value)}
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="entry-field-new-type">Type</Label>
          <NativeSelect
            id="entry-field-new-type"
            value={type}
            onChange={event => setType(event.target.value as FieldType)}
          >
            {FIELD_TYPES.map(fieldType => (
              <option key={fieldType} value={fieldType}>
                {FIELD_TYPE_LABELS[fieldType]}
              </option>
            ))}
          </NativeSelect>
        </div>
        {type === "select" && (
          <div className="grid gap-2 sm:col-span-2">
            <Label htmlFor="entry-field-new-choices">
              Choices, separated by commas
            </Label>
            <Input
              id="entry-field-new-choices"
              value={choices}
              onChange={event => setChoices(event.target.value)}
            />
          </div>
        )}
        {type === "entry" && (
          <div className="grid gap-2">
            <Label htmlFor="entry-field-new-target">Links to</Label>
            <NativeSelect
              id="entry-field-new-target"
              value={target}
              onChange={event => setTarget(event.target.value as EntryKind)}
            >
              {ENTRY_KINDS.map(entryKind => (
                <option key={entryKind} value={entryKind}>
                  {ENTRY_KIND_LABELS[entryKind].label}
                </option>
              ))}
            </NativeSelect>
          </div>
        )}
      </div>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox
          id="entry-field-new-gm-only"
          checked={gmOnly}
          onCheckedChange={checked => setGmOnly(checked)}
        />
        GM only: players never see this field or its values
      </label>
      {create.error && (
        <Alert id="entry-field-new-error" variant="destructive">
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
      <Button
        id="entry-field-new-submit"
        type="submit"
        disabled={create.isPending || label.trim() === ""}
      >
        <PlusIcon aria-hidden="true" data-icon="inline-start" />
        Add field
      </Button>
    </form>
  );
}
