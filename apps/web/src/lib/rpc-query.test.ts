import { test } from "node:test";
import assert from "node:assert/strict";
import { QueryClient } from "@tanstack/react-query";
import { listNotes } from "@atlas/api-client";

import { rpcKey } from "./rpc-query.ts";
import { profileQueryOptions } from "../hooks/use-profile.ts";
import { notesQueryOptions } from "../hooks/use-notes.ts";

test("one partial key matches the active and archived lists of a campaign only", () => {
  const client = new QueryClient();
  for (const [campaignId, archived] of [
    ["a", false],
    ["a", true],
    ["b", false],
  ] as const)
    client.setQueryData(notesQueryOptions(campaignId, archived).queryKey, []);

  const matches = (campaignId: string) =>
    client.getQueryCache().findAll({
      queryKey: rpcKey(listNotes, { input: { campaignId } }),
    }).length;
  assert.equal(matches("a"), 2);
  assert.equal(matches("b"), 1);
  assert.equal(matches("c"), 0);
});

test("actions without input get separate keys per scope", () => {
  assert.notDeepEqual(
    profileQueryOptions("owner").queryKey,
    profileQueryOptions("other").queryKey
  );
});
