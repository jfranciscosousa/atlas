import { useSuspenseQuery } from "@tanstack/react-query";
import {
  createCharacter,
  getCharacter,
  listCharacters,
  renameCharacter,
} from "@atlas/api-client";

import { rpcKey, rpcQuery, useRpcMutation } from "../lib/rpc-query.ts";

const charactersKey = (campaignId: string) =>
  rpcKey(listCharacters, { input: { campaignId } });

export function charactersQueryOptions(campaignId: string) {
  return rpcQuery(
    listCharacters,
    run =>
      run({
        input: { campaignId },
        fields: ["id", "name", "playerName", "isMine"],
      }),
    { fallback: "Could not load the characters." }
  );
}

export function useCharactersList(campaignId: string) {
  return useSuspenseQuery(charactersQueryOptions(campaignId));
}

// No list refetch here: the list route reloads on every visit, and a refetch would flash the
// new character in the list before its page opens.
export function useCharacterCreate(campaignId: string) {
  return useRpcMutation(
    createCharacter,
    (run, _: void) => run({ input: { campaignId }, fields: ["id"] }),
    { fallback: "Could not create the character." }
  );
}

export type CharacterSection = "description" | "secret_notes";

// A player's request for the secret notes comes back empty. Only the GM's page reads them.
export function characterQueryOptions(characterId: string) {
  return rpcQuery(
    getCharacter,
    run =>
      run({
        getBy: { id: characterId },
        fields: [
          "id",
          "campaignId",
          "name",
          "playerName",
          "isMine",
          "descriptionJson",
          "secretNotesJson",
        ],
      }),
    {
      fallback: "Character not found.",
      // The editor owns the document after load. A refetch must not replace it.
      staleTime: Infinity,
    }
  );
}

export function useCharacter(characterId: string) {
  return useSuspenseQuery(characterQueryOptions(characterId));
}

export function useCharacterRename(campaignId: string, characterId: string) {
  return useRpcMutation(
    renameCharacter,
    (run, name: string | null) =>
      run({ identity: characterId, input: { name }, fields: ["name"] }),
    {
      fallback: "Could not rename the character.",
      // Refetching the character would hand the open editor an older revision.
      onSuccess: (renamed, queryClient) =>
        queryClient.setQueryData(
          characterQueryOptions(characterId).queryKey,
          character => character && { ...character, ...renamed }
        ),
      invalidate: [charactersKey(campaignId)],
    }
  );
}
