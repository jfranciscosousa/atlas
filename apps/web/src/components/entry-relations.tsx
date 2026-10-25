import { useState } from "react";
import { EyeOffIcon, PlusIcon, XIcon } from "lucide-react";
import { Link } from "@tanstack/react-router";

import { NativeSelect } from "./ui/native-select";
import { Label } from "./ui/label";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { Alert, AlertDescription } from "./ui/alert";
import {
  ENTRY_KIND_LABELS,
  ENTRY_KINDS,
  endKindLabel,
  endPath,
  type RelationSpec,
} from "../lib/entry-kinds";
import {
  useEntriesList,
  useEntryKinds,
  useEntryRelations,
  useRelationCreate,
  useRelationDelete,
} from "../hooks/use-entries";
import { useCharactersList } from "../hooks/use-characters";

const capitalize = (text: string) =>
  text.charAt(0).toUpperCase() + text.slice(1);

/**
 * The relations of an entry or a character, in both directions: "Member of: Guild" and
 * "Members: Vex". A person sees a relation only when they read both ends. The GM adds and
 * removes relations. The preview shows what a player reads.
 */
export function EntryRelations({
  campaignId,
  endId,
  endKind,
  canManage,
  preview = false,
}: {
  campaignId: string;
  endId: string;
  endKind: string;
  canManage: boolean;
  preview?: boolean;
}) {
  const specs = useEntryKinds().relations;
  const relations = useEntryRelations(campaignId, endId).data.filter(
    // The GM's list holds relations that players cannot read. The preview drops them.
    relation => !preview || (relation.fromShown && relation.toShown)
  );
  const remove = useRelationDelete(campaignId);

  const rows = relations.map(relation => {
    const spec = specs.find(spec => spec.relation === relation.relation);
    const outgoing = relation.fromId === endId;
    const other = outgoing
      ? {
          kind: relation.toKind,
          id: relation.toId,
          name: relation.toName,
          shown: relation.toShown,
        }
      : {
          kind: relation.fromKind,
          id: relation.fromId,
          name: relation.fromName,
          shown: relation.fromShown,
        };
    return {
      id: relation.id,
      label: relation.label,
      text: outgoing ? spec?.label : spec?.inverse,
      other,
    };
  });

  if (rows.length === 0 && !canManage) return null;

  return (
    <section id="entry-relations" aria-label="Relations" className="space-y-3">
      <h2 className="font-heading text-xl font-semibold">Relations</h2>
      {rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">No relations yet.</p>
      ) : (
        <ul className="grid gap-2">
          {rows.map(row => (
            <li
              key={row.id}
              id={`relation-${row.id}`}
              className="flex flex-wrap items-center gap-2 rounded-2xl border bg-card px-4 py-2 text-sm"
            >
              <span className="text-muted-foreground">
                {capitalize(row.text ?? "")}
              </span>
              <Link
                to={endPath(campaignId, row.other.kind, row.other.id, preview)}
                className="font-medium text-primary underline-offset-4 hover:underline"
              >
                {row.other.name}
              </Link>
              <Badge variant="outline">{endKindLabel(row.other.kind)}</Badge>
              {row.label && (
                <span className="text-muted-foreground">({row.label})</span>
              )}
              {canManage && !row.other.shown && (
                <Badge
                  variant="outline"
                  title="Players cannot read this entry, so they do not see this relation."
                >
                  <EyeOffIcon aria-hidden="true" data-icon="inline-start" />
                  Hidden from players
                </Badge>
              )}
              {canManage && (
                <Button
                  variant="ghost"
                  size="icon"
                  className="ml-auto size-7"
                  aria-label={`Remove: ${row.text} ${row.other.name}`}
                  title="Remove"
                  disabled={remove.isPending}
                  onClick={() => remove.mutate(row.id)}
                >
                  <XIcon />
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
      {remove.error && (
        <Alert id="relation-remove-error" variant="destructive">
          <AlertDescription>{remove.error.message}</AlertDescription>
        </Alert>
      )}
      {canManage && (
        <AddRelation
          campaignId={campaignId}
          endId={endId}
          endKind={endKind}
          specs={specs}
        />
      )}
    </section>
  );
}

// "out:member_of" means this entry is the first end. "in:member_of" means it is the second.
type Choice = { direction: "out" | "in"; spec: RelationSpec };

function AddRelation({
  campaignId,
  endId,
  endKind,
  specs,
}: {
  campaignId: string;
  endId: string;
  endKind: string;
  specs: RelationSpec[];
}) {
  const entries = useEntriesList(campaignId).data;
  const characters = useCharactersList(campaignId).data;
  const create = useRelationCreate(campaignId);
  const [choice, setChoice] = useState("");
  const [target, setTarget] = useState("");
  const [label, setLabel] = useState("");

  const choices: Record<string, Choice> = {};
  for (const spec of specs) {
    if (spec.from.includes(endKind))
      choices[`out:${spec.relation}`] = { direction: "out", spec };
    // A symmetric relation reads the same both ways, so one choice is enough.
    if (spec.to.includes(endKind) && spec.label !== spec.inverse)
      choices[`in:${spec.relation}`] = { direction: "in", spec };
  }
  const chosen = choices[choice];
  const otherKinds = chosen
    ? chosen.direction === "out"
      ? chosen.spec.to
      : chosen.spec.from
    : [];
  const targets = [
    ...ENTRY_KINDS.filter(kind => otherKinds.includes(kind)).map(kind => ({
      kind: kind as string,
      heading: ENTRY_KIND_LABELS[kind].plural,
      options: entries
        .filter(entry => entry.kind === kind && entry.id !== endId)
        .map(entry => ({ id: entry.id, name: entry.name })),
    })),
    ...(otherKinds.includes("character")
      ? [
          {
            kind: "character",
            heading: "Characters",
            options: characters
              .filter(character => character.id !== endId)
              .map(character => ({
                id: character.id,
                name: character.name ?? "Unnamed character",
              })),
          },
        ]
      : []),
  ].filter(group => group.options.length > 0);
  const picked = targets
    .flatMap(group =>
      group.options.map(option => ({ ...option, kind: group.kind }))
    )
    .find(option => option.id === target);

  function add() {
    if (!chosen || !picked) return;
    const ends =
      chosen.direction === "out"
        ? {
            fromKind: endKind,
            fromId: endId,
            toKind: picked.kind,
            toId: picked.id,
          }
        : {
            fromKind: picked.kind,
            fromId: picked.id,
            toKind: endKind,
            toId: endId,
          };
    create.mutate(
      {
        ...ends,
        relation: chosen.spec.relation,
        ...(label.trim() && { label: label.trim() }),
      } as Parameters<typeof create.mutate>[0],
      {
        onSuccess: () => {
          setTarget("");
          setLabel("");
        },
      }
    );
  }

  return (
    <div
      id="relation-add"
      className="grid gap-3 rounded-2xl border border-dashed p-4 sm:grid-cols-[1fr_1.5fr_1fr_auto] sm:items-end"
    >
      <div className="grid gap-2">
        <Label htmlFor="relation-kind">Relation</Label>
        <NativeSelect
          id="relation-kind"
          value={choice}
          onChange={event => {
            setChoice(event.target.value);
            setTarget("");
          }}
        >
          <option value="">Choose…</option>
          {Object.entries(choices).map(([key, option]) => (
            <option key={key} value={key}>
              {capitalize(
                option.direction === "out"
                  ? option.spec.label
                  : option.spec.inverse
              )}
            </option>
          ))}
        </NativeSelect>
      </div>
      <div className="grid gap-2">
        <Label htmlFor="relation-target">With</Label>
        <NativeSelect
          id="relation-target"
          value={target}
          disabled={!chosen}
          onChange={event => setTarget(event.target.value)}
        >
          <option value="">
            {chosen ? "Choose…" : "Choose a relation first"}
          </option>
          {targets.map(group => (
            <optgroup key={group.kind} label={group.heading}>
              {group.options.map(option => (
                <option key={option.id} value={option.id}>
                  {option.name}
                </option>
              ))}
            </optgroup>
          ))}
        </NativeSelect>
      </div>
      <div className="grid gap-2">
        <Label htmlFor="relation-label">Label (optional)</Label>
        <Input
          id="relation-label"
          maxLength={100}
          placeholder="staff"
          value={label}
          onChange={event => setLabel(event.target.value)}
        />
      </div>
      <Button
        id="relation-add-button"
        isLoading={create.isPending}
        disabled={!chosen || !picked || create.isPending}
        onClick={add}
      >
        <PlusIcon aria-hidden="true" data-icon="inline-start" />
        Add
      </Button>
      {create.error && (
        <Alert
          id="relation-add-error"
          variant="destructive"
          className="sm:col-span-4"
        >
          <AlertDescription>{create.error.message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
