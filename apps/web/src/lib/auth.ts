export type AuthField = "email" | "password" | "password_confirmation";

export class AuthError extends Error {
  fields: Partial<Record<AuthField, string>>;

  constructor(message: string, fields: Partial<Record<AuthField, string>> = {}) {
    super(message);
    this.name = "AuthError";
    this.fields = fields;
  }
}

export type Session = {
  user: { id: string; email: string } | null;
  csrfToken: string;
};

export async function sessionRequest(
  path: string,
  options: { method?: string; csrfToken?: string; user?: Record<string, string> } = {},
): Promise<Session> {
  const response = await fetch(path, {
    method: options.method ?? "GET",
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      Accept: "application/json",
      ...(options.csrfToken ? { "x-csrf-token": options.csrfToken } : {}),
      ...(options.user ? { "Content-Type": "application/json" } : {}),
    },
    ...(options.user ? { body: JSON.stringify({ user: options.user }) } : {}),
  });

  if (response.status === 403) {
    throw new AuthError("Your session expired. Reload the page and try again.");
  }

  if (!response.headers.get("content-type")?.includes("application/json")) {
    throw new AuthError("The server is unavailable. Reload the page and try again.");
  }

  const data = await response.json();
  if (!response.ok) {
    throw new AuthError(data.error ?? "Something went wrong. Please try again.", data.fields);
  }
  return data;
}
