import { queryOptions, useMutation, useQueryClient, useSuspenseQuery } from "@tanstack/react-query";
import { createTodo, destroyTodo, listTodos, updateTodo } from "@lemonade-stand/api-client";
import { rpcOptions } from "../lib/rpc.ts";

export function todosQueryOptions(userId: string) {
  return queryOptions({
    queryKey: ["todos", userId],
    queryFn: async ({ signal, meta }) => {
      const config = rpcOptions(meta);
      const result = await listTodos({
        ...config,
        fields: ["id", "title", "completed"],
        fetchOptions: { ...config.fetchOptions, signal },
      });
      if (!result.success) throw new Error(result.errors[0]?.message ?? "Could not load todos.");
      return result.data;
    },
    staleTime: 30_000,
    retry: false,
  });
}

export function useTodosList(userId: string) {
  return useSuspenseQuery(todosQueryOptions(userId));
}

export function useTodosCreate(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (title: string, { meta }) => {
      const result = await createTodo({ ...rpcOptions(meta), input: { title } });
      if (!result.success) throw new Error(result.errors[0]?.message ?? "Could not add the todo.");
      return result.data;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["todos", userId] }),
  });
}

export function useTodosUpdate(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, completed }: { id: string; completed: boolean }, { meta }) => {
      const result = await updateTodo({ ...rpcOptions(meta), identity: id, input: { completed } });
      if (!result.success) throw new Error(result.errors[0]?.message ?? "Could not update the todo.");
      return result.data;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["todos", userId] }),
  });
}

export function useTodosDelete(userId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string, { meta }) => {
      const result = await destroyTodo({ ...rpcOptions(meta), identity: id });
      if (!result.success) throw new Error(result.errors[0]?.message ?? "Could not delete the todo.");
      return result.data;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["todos", userId] }),
  });
}
