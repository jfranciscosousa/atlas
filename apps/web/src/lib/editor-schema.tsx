import { createReactInlineContentSpec } from "@blocknote/react";
import { BlockNoteSchema, defaultInlineContentSpecs } from "@blocknote/core";

import { blockSpecs, mentionConfig, parseMention } from "./blocknote-schema";
import { MentionChip } from "../components/mention-chip";

export const schema = BlockNoteSchema.create({
  blockSpecs,
  inlineContentSpecs: {
    ...defaultInlineContentSpecs,
    mention: createReactInlineContentSpec(mentionConfig, {
      parse: parseMention,
      render: ({ inlineContent }) => (
        <MentionChip
          kind={inlineContent.props.kind}
          id={inlineContent.props.id}
        />
      ),
    }),
  },
});
