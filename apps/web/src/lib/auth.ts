import type { QueryClient } from "@tanstack/react-query";

export type AuthField = "email" | "password" | "password_confirmation";

export class AuthError extends Error {
  fields: Partial<Record<AuthField, string>>;

  constructor(
    message: string,
    fields: Partial<Record<AuthField, string>> = {}
  ) {
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
  options: {
    method?: string;
    user?: Record<string, string>;
    queryClient?: QueryClient;
  } = {}
): Promise<Session> {
  const csrfToken =
    options.queryClient?.getDefaultOptions().mutations?.meta?.csrfToken;
  const response = await fetch(path, {
    method: options.method ?? "GET",
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      Accept: "application/json",
      ...(csrfToken ? { "x-csrf-token": csrfToken } : {}),
      ...(options.user ? { "Content-Type": "application/json" } : {}),
    },
    ...(options.user ? { body: JSON.stringify({ user: options.user }) } : {}),
  });

  if (response.status === 403) {
    throw new AuthError("Your session expired. Reload the page and try again.");
  }

  if (!response.headers.get("content-type")?.includes("application/json")) {
    throw new AuthError(
      "The server is unavailable. Reload the page and try again."
    );
  }

  const data = await response.json();
  if (!response.ok) {
    throw new AuthError(
      data.error ?? "Something went wrong. Please try again.",
      data.fields
    );
  }
  if (options.queryClient) {
    const defaults = options.queryClient.getDefaultOptions();
    const meta = { csrfToken: data.csrfToken };
    options.queryClient.setDefaultOptions({
      ...defaults,
      queries: { ...defaults.queries, meta },
      mutations: { ...defaults.mutations, meta },
    });
  }
  return data;
}
