import { defaultBlockSpecs } from "@blocknote/core";

// The server accepts only these blocks. Audio, video and file blocks are left out so the editor
// never produces a document the server would reject.
const { audio, video, file, ...blockSpecs } = defaultBlockSpecs;
void audio;
void video;
void file;

export { blockSpecs };

export const MENTION_KINDS = ["character", "session", "note"] as const;
export type MentionKind = (typeof MENTION_KINDS)[number];

// The document stores the kind and the ID of the entry, never its name. This file has no React,
// so the fixture script can load it under Node.
export const mentionConfig = {
  type: "mention",
  propSchema: {
    kind: { default: "character", values: MENTION_KINDS },
    id: { default: "" },
  },
  content: "none",
} as const;

// Markdown imports and HTML pastes must keep Atlas links as mentions, not web links.
export function parseMention(element: HTMLElement) {
  if (element.tagName !== "A") return undefined;
  const match = element
    .getAttribute("href")
    ?.match(
      /^atlas-entry:(character|session|note):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/
    );
  if (!match) return undefined;
  return { kind: match[1] as MentionKind, id: match[2]! };
}

// A chip copied from the editor links to its page, and BlockNote parses that as a web link, which
// the server rejects. The chip also carries its kind and ID, so the paste uses the Atlas link.
export function mentionsToAtlasLinks(html: string) {
  const dom = document.createElement("template");
  dom.innerHTML = html;
  for (const chip of dom.content.querySelectorAll<HTMLElement>(
    'a[data-inline-content-type="mention"]'
  ))
    chip.setAttribute(
      "href",
      `atlas-entry:${chip.dataset.kind}:${chip.dataset.id}`
    );
  return dom.innerHTML;
}

/** The native BlockNote block array, as the API sends and stores it. */
export type BlockNoteDocument = Array<Record<string, unknown>>;
