import * as Y from "yjs";
// Writes the BlockNote <-> Yjs fixtures that the API tests use as an oracle:
//   node scripts/export-yjs-fixtures.mts ../api/test/support/fixtures/blocknote_yjs.json
// Run it again after a BlockNote upgrade and check the API tests.
import { writeFileSync } from "node:fs";
import { ServerBlockNoteEditor } from "@blocknote/server-util";
import {
  BlockNoteSchema,
  createInlineContentSpec,
  defaultInlineContentSpecs,
} from "@blocknote/core";

import { blockSpecs, mentionConfig } from "../src/lib/blocknote-schema.ts";

// Same config as the editor's schema. Only the rendering differs, and the server never renders.
const schema = BlockNoteSchema.create({
  blockSpecs,
  inlineContentSpecs: {
    ...defaultInlineContentSpecs,
    mention: createInlineContentSpec(mentionConfig, {
      render: () => ({ dom: undefined as unknown as HTMLElement }),
    }),
  },
});

const FRAGMENT = "document-store";
const editor = ServerBlockNoteEditor.create({ schema });
const text = (t: string, styles = {}) => ({ type: "text", text: t, styles });
const cell = (t: string, props = {}) => ({
  type: "tableCell",
  content: [text(t)],
  props: {
    colspan: 1,
    rowspan: 1,
    backgroundColor: "default",
    textColor: "default",
    textAlignment: "left",
    ...props,
  },
});
const mention = (kind: string, id: string) => ({
  type: "mention",
  props: { kind, id },
});
const IMAGE = "atlas-image:11111111-1111-1111-1111-111111111111";

const cases: Record<string, any[]> = {
  styles: [
    {
      id: "p1",
      type: "paragraph",
      content: [
        text("plain "),
        text("bold", { bold: true }),
        text(" "),
        text("all", {
          bold: true,
          italic: true,
          underline: true,
          strike: true,
          code: true,
        }),
        text(" "),
        text("red", { textColor: "red", backgroundColor: "yellow" }),
      ],
    },
  ],
  links: [
    {
      id: "p1",
      type: "paragraph",
      content: [
        text("see "),
        {
          type: "link",
          href: "https://example.org/a?b=1",
          content: [
            text("a link", { italic: true }),
            text(" bold", { bold: true }),
          ],
        },
        text(" and "),
        { type: "link", href: "mailto:a@b.co", content: [text("mail")] },
      ],
    },
  ],
  nested: [
    {
      id: "p1",
      type: "paragraph",
      content: [text("parent")],
      children: [
        {
          id: "b1",
          type: "bulletListItem",
          content: [text("one")],
          children: [
            {
              id: "b2",
              type: "numberedListItem",
              props: { start: 3 },
              content: [text("deep")],
            },
          ],
        },
        {
          id: "c1",
          type: "checkListItem",
          props: { checked: true },
          content: [text("done")],
        },
        { id: "t1", type: "toggleListItem", content: [text("toggle")] },
      ],
    },
  ],
  headings: [
    { id: "h1", type: "heading", props: { level: 1 }, content: [text("One")] },
    {
      id: "h2",
      type: "heading",
      props: { level: 3, isToggleable: true },
      content: [text("Three")],
    },
  ],
  table: [
    {
      id: "t1",
      type: "table",
      content: {
        type: "tableContent",
        columnWidths: [120, undefined],
        headerRows: 1,
        rows: [
          { cells: [cell("h1"), cell("h2")] },
          { cells: [cell("a", { textAlignment: "center" }), cell("b")] },
        ],
      },
    },
  ],
  media: [
    {
      id: "i1",
      type: "image",
      props: {
        url: IMAGE,
        caption: "A caption",
        name: "map.png",
        showPreview: true,
        previewWidth: 320,
      },
    },
    { id: "d1", type: "divider" },
    {
      id: "k1",
      type: "codeBlock",
      props: { language: "js" },
      content: [text("let a = 1;\nlet b = 2;")],
    },
    { id: "q1", type: "quote", content: [text("quoted")] },
  ],
  mentions: [
    {
      id: "p1",
      type: "paragraph",
      content: [
        text("met "),
        mention("character", "11111111-1111-1111-1111-111111111111"),
        mention("session", "22222222-2222-2222-2222-222222222222"),
        text(" and "),
        text("bold", { bold: true }),
        mention("note", "33333333-3333-3333-3333-333333333333"),
      ],
      children: [
        {
          id: "b1",
          type: "bulletListItem",
          content: [mention("note", "33333333-3333-3333-3333-333333333333")],
        },
      ],
    },
    {
      id: "t1",
      type: "table",
      content: {
        type: "tableContent",
        rows: [
          {
            cells: [
              {
                type: "tableCell",
                content: [
                  text("in a cell "),
                  mention("session", "22222222-2222-2222-2222-222222222222"),
                ],
                props: {
                  colspan: 1,
                  rowspan: 1,
                  backgroundColor: "default",
                  textColor: "default",
                  textAlignment: "left",
                },
              },
            ],
          },
        ],
      },
    },
  ],
  breaks_and_unicode: [
    { id: "p1", type: "paragraph", content: [text("line one\nline two 😀 é")] },
    { id: "p2", type: "paragraph", content: [] },
  ],
};

// Marks and attributes exactly as the browser editor writes them, not as the server util does.
function tree(node: any): unknown {
  if (node instanceof Y.XmlText)
    return { text: node.toDelta(), attrs: node.getAttributes() };
  return {
    tag: node.nodeName,
    attrs: node.getAttributes(),
    children: node.toArray().map(tree),
  };
}

const out = Object.entries(cases).map(([name, blocks]) => {
  const doc = editor.blocksToYDoc(blocks as any, FRAGMENT);
  return {
    name,
    blocks,
    update: Buffer.from(Y.encodeStateAsUpdate(doc)).toString("base64"),
    tree: doc.getXmlFragment(FRAGMENT).toArray().map(tree),
    output: editor.yDocToBlocks(doc, FRAGMENT),
  };
});

const props = Object.fromEntries(
  Object.entries(schema.blockSpecs).map(([k, s]: any) => [
    k,
    Object.keys(s.config.propSchema),
  ])
);
const inline = Object.fromEntries(
  Object.entries(schema.inlineContentSpecs)
    .filter(([, s]: any) => s.config.content === "none")
    .map(([k, s]: any) => [k, Object.keys(s.config.propSchema)])
);
writeFileSync(
  process.argv[2]!,
  JSON.stringify({ fragment: FRAGMENT, props, inline, cases: out }, null, 1)
);
