import { BlockNoteSchema, defaultBlockSpecs } from "@blocknote/core";

// The server accepts only these blocks. Audio, video and file blocks are left out so the editor
// never produces a document the server would reject.
const { audio, video, file, ...blockSpecs } = defaultBlockSpecs;
void audio;
void video;
void file;

export const schema = BlockNoteSchema.create({ blockSpecs });

/** The native BlockNote block array, as the API sends and stores it. */
export type BlockNoteDocument = Array<Record<string, unknown>>;
