import { useForm } from "@tanstack/react-form";
import { useTodosCreate, useTodosDelete, useTodosList, useTodosUpdate } from "../hooks/use-todos";

export function TodoList({ userId }: { userId: string }) {
  const query = useTodosList(userId);
  const create = useTodosCreate(userId);
  const update = useTodosUpdate(userId);
  const remove = useTodosDelete(userId);
  const todos = query.data;
  const isPending = create.isPending || update.isPending || remove.isPending;
  const error = create.error ?? update.error ?? remove.error ?? query.error;

  function resetErrors() {
    create.reset();
    update.reset();
    remove.reset();
  }

  const form = useForm({
    defaultValues: { title: "" },
    onSubmit: async ({ value }) => {
      resetErrors();
      try {
        await create.mutateAsync(value.title);
        form.reset();
      } catch {
        // The mutation exposes the error below and preserves the title for retry.
      }
    },
  });

  return (
    <section id="todos" aria-labelledby="todos-heading" className="mt-8 border-t border-emerald-950/10 pt-7">
      <div className="flex items-center justify-between gap-3">
        <h2 id="todos-heading" className="text-lg font-semibold">Your todos</h2>
        <span className="text-xs text-emerald-950/60">{todos.filter((todo) => !todo.completed).length} remaining</span>
      </div>
      <form id="todo-form" className="mt-5" onSubmit={(event) => {
        event.preventDefault();
        if (!isPending) void form.handleSubmit();
      }}>
        <form.Field name="title">
          {(field) => (
            <>
              <label htmlFor="todo-title" className="mb-2 block text-sm font-medium">What do you need to do?</label>
              <div className="flex gap-2">
                <input
                  id="todo-title"
                  name="title"
                  required
                  maxLength={200}
                  disabled={create.isPending}
                  value={field.state.value}
                  onChange={(event) => field.handleChange(event.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="Buy lemons"
                  className="min-w-0 flex-1 rounded-xl border border-emerald-950/20 px-3 py-2 text-sm outline-none transition focus:border-emerald-700 focus:ring-3 focus:ring-emerald-100"
                />
                <button id="todo-add" type="submit" disabled={isPending || !field.state.value.trim()} className="primary-button shrink-0">
                  {create.isPending ? "Adding…" : "Add"}
                </button>
              </div>
            </>
          )}
        </form.Field>
      </form>
      {error && <p id="todo-error" role="alert" className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-800">{error.message}</p>}
      {todos.length === 0 ? (
        <p id="todos-empty" className="mt-6 text-sm text-emerald-950/60">No todos yet. Add your first one above.</p>
      ) : (
        <ul id="todo-list" className="mt-5 divide-y divide-emerald-950/10">
          {todos.map((todo) => (
            <li id={`todo-${todo.id}`} key={todo.id} aria-busy={(update.isPending && update.variables?.id === todo.id) || (remove.isPending && remove.variables === todo.id)} className="flex items-center gap-3 py-4">
              <input
                id={`todo-completed-${todo.id}`}
                type="checkbox"
                checked={todo.completed}
                disabled={isPending}
                onChange={() => {
                  resetErrors();
                  update.mutate({ id: todo.id, completed: !todo.completed });
                }}
                className="size-4 shrink-0 accent-emerald-800 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-emerald-800"
              />
              <label htmlFor={`todo-completed-${todo.id}`} className={`min-w-0 flex-1 break-words text-sm ${todo.completed ? "text-emerald-950/45 line-through" : ""}`}>
                {todo.title}
              </label>
              <button
                id={`todo-delete-${todo.id}`}
                type="button"
                disabled={isPending}
                onClick={() => {
                  resetErrors();
                  remove.mutate(todo.id);
                }}
                aria-label={`Delete ${todo.title}`}
                className="rounded px-1 py-2 text-xs text-emerald-950/60 transition hover:text-red-700 focus-visible:outline-2 focus-visible:outline-offset-2 disabled:opacity-40"
              >Delete</button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
