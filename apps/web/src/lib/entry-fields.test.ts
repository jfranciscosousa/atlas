import { test } from "node:test";
import assert from "node:assert/strict";

import {
  choiceUpdate,
  inputToValue,
  playerValues,
  valueText,
  type CustomValue,
} from "./entry-fields.ts";

const value = (extra: Partial<CustomValue>): CustomValue => ({
  id: "f1",
  label: "Field",
  type: "text",
  gm_only: false,
  position: 0,
  choices: null,
  target_kind: null,
  value: null,
  ...extra,
});

test("the preview drops GM-only fields and restricts an entry that is not shown", () => {
  const values = [
    value({ id: "a", label: "Dragonmark", value: "Mark of Making" }),
    value({
      id: "b",
      label: "True allegiance",
      type: "entry",
      gm_only: true,
      value: {
        kind: "faction",
        id: "x",
        label: "House Cannith",
        restricted: false,
        shown: true,
      },
    }),
    value({
      id: "c",
      label: "Kingdom",
      type: "entry",
      value: {
        kind: "location",
        id: "y",
        label: "Aundair",
        restricted: false,
        shown: false,
      },
    }),
  ];
  const seen = playerValues(values);
  assert.deepEqual(
    seen.map(v => v.label),
    ["Dragonmark", "Kingdom"]
  );
  assert.equal(valueText(seen[1]), "Restricted entry");
  assert.equal(JSON.stringify(seen).includes("Aundair"), false);
  assert.equal(JSON.stringify(seen).includes('"y"'), false);
});

test("a value reads as text", () => {
  assert.equal(valueText(value({ value: null })), null);
  assert.equal(valueText(value({ type: "number", value: 0 })), "0");
  assert.equal(valueText(value({ type: "boolean", value: false })), "No");
  assert.equal(valueText(value({ type: "boolean", value: true })), "Yes");
});

test("an input becomes a value, and an empty input clears", () => {
  assert.equal(inputToValue("text", "  Mark "), "Mark");
  assert.equal(inputToValue("text", "  "), null);
  assert.equal(inputToValue("number", "3.5"), 3.5);
  assert.equal(inputToValue("number", "0"), 0);
  assert.equal(inputToValue("number", "x"), undefined);
  assert.equal(inputToValue("boolean", "false"), false);
  assert.equal(inputToValue("boolean", ""), null);
});

test("the choice editor sends renames for saved choices that changed", () => {
  assert.deepEqual(
    choiceUpdate([
      { original: "Preserver", text: "Preserver" },
      { original: "Defiler", text: " Despoiler " },
      { original: null, text: "Templar" },
      { original: "Gone", text: "" },
    ]),
    {
      choices: ["Preserver", "Despoiler", "Templar"],
      renamedChoices: { Defiler: "Despoiler" },
    }
  );
  assert.deepEqual(choiceUpdate([{ original: "A", text: "A" }]), {
    choices: ["A"],
  });
});
