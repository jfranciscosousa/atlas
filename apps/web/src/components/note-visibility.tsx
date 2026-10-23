import { EyeIcon } from "lucide-react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { useNoteVisibility, type NoteVisibility } from "../hooks/use-notes";
import { useCharactersList } from "../hooks/use-characters";

const LABELS: Record<NoteVisibility, string> = {
  only_me: "Private",
  me_and_gm: "Owner and GM",
  character: "Character",
  everyone: "Everyone",
};

const HINTS: Record<NoteVisibility, string> = {
  only_me: "Only its owner can read this note.",
  me_and_gm: "Only its owner and the GM can read this note.",
  character:
    "Its owner, the GM, and the player of the linked character can read this note.",
  everyone: "Every player in the campaign can read this note.",
};

export function NoteVisibilityBadge({
  visibility,
  characterName,
}: {
  visibility: NoteVisibility;
  characterName: string | null;
}) {
  return (
    <Badge
      variant={visibility === "everyone" ? "secondary" : "outline"}
      title={HINTS[visibility]}
    >
      {visibility === "character" && characterName
        ? `Character: ${characterName}`
        : LABELS[visibility]}
    </Badge>
  );
}

/** Sets who reads a note. Owner and GM only. A player may link only their own character. */
export function NoteVisibilityMenu({
  campaignId,
  id,
  visibility,
  characterId,
  isGm,
  title,
  icon = false,
}: {
  campaignId: string;
  id: string;
  visibility: NoteVisibility;
  characterId: string | null;
  isGm: boolean;
  title: string;
  icon?: boolean;
}) {
  const characters = useCharactersList(campaignId).data.filter(
    character => isGm || character.isMine
  );
  const setVisibility = useNoteVisibility(campaignId);
  const value =
    visibility === "character" ? `character:${characterId}` : visibility;
  const label = "Who can read";

  function choose(next: string) {
    if (next.startsWith("character:"))
      setVisibility.mutate({
        id,
        visibility: "character",
        characterId: next.slice("character:".length),
      });
    else setVisibility.mutate({ id, visibility: next as NoteVisibility });
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            id={`note-visibility-${id}`}
            variant={icon ? "ghost" : "outline"}
            size={icon ? "icon" : "default"}
            aria-label={icon ? `${label}: ${title}` : undefined}
            title={label}
            disabled={setVisibility.isPending}
          />
        }
      >
        <EyeIcon
          aria-hidden="true"
          data-icon={icon ? undefined : "inline-start"}
        />
        {!icon && label}
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-56">
        <DropdownMenuRadioGroup value={value} onValueChange={choose}>
          <DropdownMenuGroup>
            <DropdownMenuLabel>{label}</DropdownMenuLabel>
          </DropdownMenuGroup>
          <DropdownMenuRadioItem value="only_me">
            {LABELS.only_me}
          </DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="me_and_gm">
            {LABELS.me_and_gm}
          </DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="everyone">
            {LABELS.everyone}
          </DropdownMenuRadioItem>
          {characters.length > 0 && <DropdownMenuSeparator />}
          {characters.map(character => (
            <DropdownMenuRadioItem
              key={character.id}
              value={`character:${character.id}`}
            >
              Character: {character.name ?? "Unnamed character"}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
