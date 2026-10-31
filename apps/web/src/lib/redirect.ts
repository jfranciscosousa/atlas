/** Returns a same-origin path from a `redirect` search value, or undefined. */
export function safeRedirect(value: unknown): string | undefined {
  return typeof value === "string" &&
    value.startsWith("/") &&
    !value.startsWith("//") &&
    !value.includes("\\") &&
    !/[\u0000-\u0020\u007f]/.test(value)
    ? value
    : undefined;
}

const returnPathKey = "atlas.auth.return-path";
const returnPathLifetime = 60 * 60 * 1000;

type ReturnPathStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;

function browserStorage(): ReturnPathStorage | undefined {
  try {
    return typeof window === "undefined" ? undefined : window.localStorage;
  } catch {
    return undefined;
  }
}

// Email links can open in another tab, so sessionStorage cannot preserve this path.
export function rememberAuthRedirect(
  value: unknown,
  storage = browserStorage(),
  now = Date.now()
): void {
  const path = safeRedirect(value);
  if (!path) return;
  try {
    storage?.setItem(
      returnPathKey,
      JSON.stringify({ path, expiresAt: now + returnPathLifetime })
    );
  } catch {
    // The URL still carries the destination when browser storage is unavailable.
  }
}

export function authRedirect(
  value?: unknown,
  storage = browserStorage(),
  now = Date.now()
): string {
  const explicit = safeRedirect(value);
  if (explicit) return explicit;
  try {
    const saved = JSON.parse(storage?.getItem(returnPathKey) ?? "null");
    if (saved?.expiresAt > now) return safeRedirect(saved.path) ?? "/campaigns";
    storage?.removeItem(returnPathKey);
  } catch {
    // Invalid or unavailable storage must not block authentication.
  }
  return "/campaigns";
}

export function consumeAuthRedirect(
  value?: unknown,
  storage = browserStorage(),
  now = Date.now()
): string {
  const path = authRedirect(value, storage, now);
  try {
    storage?.removeItem(returnPathKey);
  } catch {
    // Authentication must also work when browser storage is unavailable.
  }
  return path;
}
