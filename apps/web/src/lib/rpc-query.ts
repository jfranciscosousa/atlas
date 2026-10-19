import {
  queryOptions,
  useMutation,
  useQueryClient,
  type QueryClient,
  type QueryKey,
} from "@tanstack/react-query";

import { rpcOptions } from "./rpc.ts";

type Result<T> =
  | { success: true; data: T }
  | { success: false; errors: { message?: string }[] };

type Action = (config: any) => Promise<Result<any>>;
type DeepPartial<T> = T extends object
  ? { [K in keyof T]?: DeepPartial<T[K]> }
  : T;

// Actions are functions, which cannot be query keys. Each gets a stable id instead.
const ids = new WeakMap<Action, string>();
let nextId = 0;
function actionId(action: Action) {
  let id = ids.get(action);
  if (!id) ids.set(action, (id = `${action.name}#${nextId++}`));
  return id;
}

/**
 * Key prefix for an action. Pass a partial config to invalidate a group of queries.
 * Actions without input need a `scope`, such as the user ID, so that users never share a cache.
 */
export function rpcKey<A extends Action>(
  action: A,
  config?: DeepPartial<Parameters<A>[0]>,
  scope?: unknown
): QueryKey {
  const key = [actionId(action), config ?? {}];
  // Without a scope the key stays a prefix of every scoped key, so invalidation still matches.
  return scope === undefined ? key : [...key, scope];
}

// Mutation variables default to the action's `input`. Annotate the parameter to override.
type InputOf<A extends Action> = Parameters<A>[0] extends { input?: infer I }
  ? Exclude<I, undefined>
  : never;

function unwrap<T>(result: Result<T>, fallback: string) {
  if (!result.success) throw new Error(result.errors[0]?.message ?? fallback);
  return result.data;
}

// Runs `call` with a spy to read the config it passes. `call` must pass its config to `run` once.
function configOf<A extends Action>(call: (run: A) => unknown) {
  let config: unknown;
  call(((c: unknown) => {
    config = c;
    return new Promise(() => {});
  }) as A);
  return config as DeepPartial<Parameters<A>[0]>;
}

// Adds the CSRF header and the abort signal. The cast keeps the action's own generics.
function withTransport<A extends Action>(
  action: A,
  meta: Parameters<typeof rpcOptions>[0],
  signal?: AbortSignal
) {
  const transport = rpcOptions(meta);
  return ((config: object) =>
    action({
      ...config,
      ...transport,
      fetchOptions: { ...transport.fetchOptions, signal },
    })) as A;
}

/**
 * `call` receives `run`, the action with its own types. The key comes from the action and the
 * config that `call` passes to `run`. The data type comes from `run`'s `fields`.
 */
export function rpcQuery<A extends Action, T>(
  action: A,
  call: (run: A) => Promise<Result<T>>,
  {
    fallback,
    scope,
    ...options
  }: { fallback: string; scope?: unknown; staleTime?: number; retry?: boolean }
) {
  return queryOptions({
    queryKey: rpcKey(action, configOf(call), scope),
    queryFn: async ({ signal, meta }) =>
      unwrap(await call(withTransport(action, meta, signal)), fallback),
    retry: false,
    ...options,
  });
}

/** `invalidate` lists keys from `rpcKey` to refetch after success. */
export function useRpcMutation<A extends Action, T, V = InputOf<A>>(
  action: A,
  call: (run: A, variables: V) => Promise<Result<T>>,
  {
    fallback,
    invalidate = [],
    onSuccess,
  }: {
    fallback: string;
    invalidate?: QueryKey[];
    onSuccess?: (data: T, queryClient: QueryClient) => unknown;
  }
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (variables: V, { meta }) =>
      unwrap(await call(withTransport(action, meta), variables), fallback),
    onSuccess: async data => {
      await onSuccess?.(data, queryClient);
      await Promise.all(
        invalidate.map(queryKey => queryClient.invalidateQueries({ queryKey }))
      );
    },
  });
}
