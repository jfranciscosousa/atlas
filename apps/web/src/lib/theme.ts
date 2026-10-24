export const THEMES = ["system", "light", "dark"] as const;
export type Theme = (typeof THEMES)[number];
export type ResolvedTheme = "light" | "dark";

export const THEME_STORAGE_KEY = "atlas-theme";

export function parseTheme(value: unknown): Theme {
  return THEMES.find(theme => theme === value) ?? "system";
}

export function resolveTheme(
  theme: Theme,
  prefersDark: boolean
): ResolvedTheme {
  if (theme === "system") return prefersDark ? "dark" : "light";
  return theme;
}

// Runs in <head> before the first paint, so a dark user never sees a light flash.
// It must stay in step with `resolveTheme` and `applyTheme`.
export const THEME_INIT_SCRIPT = `try{var t=localStorage.getItem(${JSON.stringify(THEME_STORAGE_KEY)});var d=t==="dark"||(t!=="light"&&matchMedia("(prefers-color-scheme: dark)").matches);document.documentElement.classList.toggle("dark",d);document.documentElement.style.colorScheme=d?"dark":"light"}catch(e){}`;
