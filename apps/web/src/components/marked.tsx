import { highlight } from "../lib/search";

/** The text, with each word that contains a query term marked. */
export function Marked({ text, terms }: { text: string; terms: string[] }) {
  return (
    <>
      {highlight(text, terms).map((part, index) =>
        part.match ? (
          <mark
            key={index}
            className="rounded-sm bg-gold/30 px-0.5 text-inherit"
          >
            {part.text}
          </mark>
        ) : (
          part.text
        )
      )}
    </>
  );
}
