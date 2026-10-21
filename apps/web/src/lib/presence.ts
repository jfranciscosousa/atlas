/** A person who has the section open. The server sets every field. */
export type Person = { key: string; name: string; color: string };

const MAX_SHOWN = 5;

function person(state: unknown): Person | undefined {
  const user = (state as { user?: Record<string, unknown> } | null)?.user;
  if (
    typeof user?.key === "string" &&
    typeof user.name === "string" &&
    typeof user.color === "string"
  )
    return { key: user.key, name: user.name, color: user.color };
  return undefined;
}

/**
 * Lists the other people in an awareness map (client ID to state). One person with two tabs
 * counts once. The own person (`selfKey`) and the own client never show.
 */
export function whoIsHere(
  states: Map<number, unknown>,
  selfClientId: number,
  selfKey: string | undefined
): Person[] {
  const people = new Map<string, Person>();
  for (const [clientId, state] of states) {
    const found = clientId === selfClientId ? undefined : person(state);
    if (found && found.key !== selfKey) people.set(found.key, found);
  }
  return [...people.values()].sort((a, b) => a.name.localeCompare(b.name));
}

/** The first people to show, and how many more there are. */
export function summarize(people: Person[]) {
  return {
    shown: people.slice(0, MAX_SHOWN),
    more: Math.max(0, people.length - MAX_SHOWN),
  };
}
