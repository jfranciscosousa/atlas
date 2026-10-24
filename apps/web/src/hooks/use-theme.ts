import { useCallback, useSyncExternalStore } from "react";

import {
  THEME_STORAGE_KEY,
  parseTheme,
  resolveTheme,
  type ResolvedTheme,
  type Theme,
} from "../lib/theme";

const isBrowser = typeof window !== "undefined";
const darkQuery = isBrowser ? matchMedia("(prefers-color-scheme: dark)") : null;
const listeners = new Set<() => void>();
// Used only when storage is blocked: the choice then lasts until the page closes.
let memoryTheme: Theme = "system";

function readTheme(): Theme {
  try {
    return parseTheme(localStorage.getItem(THEME_STORAGE_KEY));
  } catch {
    return memoryTheme;
  }
}

function applyTheme() {
  const resolved = resolveTheme(readTheme(), darkQuery?.matches ?? false);
  document.documentElement.classList.toggle("dark", resolved === "dark");
  document.documentElement.style.colorScheme = resolved;
}

function notify() {
  applyTheme();
  listeners.forEach(listener => listener());
}

if (isBrowser) {
  // Follow the operating system while the theme is "system", and follow other tabs.
  darkQuery?.addEventListener("change", notify);
  addEventListener("storage", event => {
    if (event.key === THEME_STORAGE_KEY) notify();
  });
}

const serverTheme = (): Theme => "system";

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => void listeners.delete(listener);
}

const subscribeToSystem = (listener: () => void) => {
  darkQuery?.addEventListener("change", listener);
  return () => darkQuery?.removeEventListener("change", listener);
};

export function useTheme() {
  const theme = useSyncExternalStore(subscribe, readTheme, serverTheme);
  const prefersDark = useSyncExternalStore(
    subscribeToSystem,
    () => darkQuery?.matches ?? false,
    () => false
  );
  const resolvedTheme: ResolvedTheme = resolveTheme(theme, prefersDark);

  const setTheme = useCallback((next: Theme) => {
    memoryTheme = next;
    try {
      if (next === "system") localStorage.removeItem(THEME_STORAGE_KEY);
      else localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch {
      // Blocked storage is handled by `memoryTheme`.
    }
    notify();
  }, []);

  return { theme, resolvedTheme, setTheme };
}
