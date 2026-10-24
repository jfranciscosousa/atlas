import { useMemo, useState } from "react";
import { useRouterState } from "@tanstack/react-router";

import { parseTarget } from "../lib/search.ts";

/** The block that a search hit pointed at, from the hash of the page address. */
export function useSearchTarget() {
  const hash = useRouterState({ select: state => state.location.hash });
  return useMemo(() => parseTarget(hash), [hash]);
}

/**
 * The open tab of a page. A search hit opens the tab that holds its section, and the person
 * can still pick another one afterwards. `tabs` maps a section name to its tab.
 */
export function useTabState(tabs: Record<string, string>, fallback: string) {
  const target = useSearchTarget();
  const [tab, setTab] = useState((target && tabs[target.section]) || fallback);
  const [seen, setSeen] = useState(target);
  if (target !== seen) {
    setSeen(target);
    const next = target && tabs[target.section];
    if (next) setTab(next);
  }
  return [tab, setTab] as const;
}
