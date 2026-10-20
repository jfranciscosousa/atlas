/** "Session 3" or "Session 3: The Sunken Keep". */
export function sessionLabel(session: {
  number: number;
  title: string | null;
}) {
  return session.title
    ? `Session ${session.number}: ${session.title}`
    : `Session ${session.number}`;
}

/** The API sends a plain date. Parse it as local time so no time zone shifts the day. */
export function formatPlayedOn(playedOn: string | null) {
  if (!playedOn) return null;
  const [year, month, day] = playedOn.split("-").map(Number);
  return new Date(year!, month! - 1, day!).toLocaleDateString(undefined, {
    dateStyle: "medium",
  });
}
