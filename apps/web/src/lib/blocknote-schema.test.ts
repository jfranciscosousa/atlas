import { test } from "node:test";
import assert from "node:assert/strict";
import { ServerBlockNoteEditor } from "@blocknote/server-util";
import {
  BlockNoteSchema,
  createInlineContentSpec,
  defaultInlineContentSpecs,
} from "@blocknote/core";

import { blockSpecs, mentionConfig, parseMention } from "./blocknote-schema.ts";

const schema = BlockNoteSchema.create({
  blockSpecs,
  inlineContentSpecs: {
    ...defaultInlineContentSpecs,
    mention: createInlineContentSpec(mentionConfig, {
      parse: parseMention,
      render: () => ({ dom: document.createElement("span") }),
    }),
  },
});
const editor = ServerBlockNoteEditor.create({ schema });
const id = "11111111-1111-1111-1111-111111111111";

test("pasted Markdown and HTML Atlas links become mentions without storing labels", async () => {
  for (const kind of ["character", "session", "note"]) {
    const href = `atlas-entry:${kind}:${id}`;
    for (const blocks of [
      await editor.tryParseMarkdownToBlocks(`Met [@Renoir](${href}) today.`),
      await editor.tryParseHTMLToBlocks(
        `<p>Met <a href="${href}">@Renoir</a> today.</p>`
      ),
    ]) {
      assert.deepEqual(blocks[0].content, [
        { type: "text", text: "Met ", styles: {} },
        { type: "mention", props: { kind, id }, content: undefined },
        { type: "text", text: " today.", styles: {} },
      ]);
    }
  }
});

test("web links stay links and malformed Atlas links do not become mentions", async () => {
  for (const href of [
    "https://example.org",
    "mailto:gm@example.org",
    `atlas-entry:player:${id}`,
    "atlas-entry:character:not-a-uuid",
    `atlas-entry:note:${id}?extra=true`,
  ]) {
    const blocks = await editor.tryParseHTMLToBlocks(
      `<p><a href="${href}">label</a></p>`
    );
    assert.deepEqual(
      blocks[0].content,
      href.startsWith("atlas-entry:")
        ? [{ type: "text", text: "label", styles: {} }]
        : [
            {
              type: "link",
              href,
              content: [{ type: "text", text: "label", styles: {} }],
            },
          ]
    );
  }
});
