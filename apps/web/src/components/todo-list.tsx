import { useForm } from "@tanstack/react-form";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Checkbox } from "./ui/checkbox";
import { Field, FieldLabel } from "./ui/field";
import { Alert, AlertDescription } from "./ui/alert";
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
    <section id="todos" aria-labelledby="todos-heading" className="mt-8 border-t border-border pt-7">
      <div className="flex items-center justify-between gap-3">
        <h2 id="todos-heading" className="text-lg font-semibold">Your todos</h2>
        <span className="text-xs text-muted-foreground">{todos.filter((todo) => !todo.completed).length} remaining</span>
      </div>
      <form id="todo-form" className="mt-5" onSubmit={(event) => {
        event.preventDefault();
        if (!isPending) void form.handleSubmit();
      }}>
        <form.Field name="title">
          {(field) => (
            <Field>
              <FieldLabel htmlFor="todo-title">What do you need to do?</FieldLabel>
              <div className="flex gap-2">
                <Input
                  id="todo-title"
                  name="title"
                  required
                  maxLength={200}
                  disabled={create.isPending}
                  value={field.state.value}
                  onChange={(event) => field.handleChange(event.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="Buy lemons"
                  className="min-w-0 flex-1"
                />
                <Button id="todo-add" type="submit" disabled={isPending || !field.state.value.trim()}>
                  {create.isPending ? "Adding…" : "Add"}
                </Button>
              </div>
            </Field>
          )}
        </form.Field>
      </form>
      {error && <Alert id="todo-error" variant="destructive" className="mt-4"><AlertDescription>{error.message}</AlertDescription></Alert>}
      {todos.length === 0 ? (
        <p id="todos-empty" className="mt-6 text-sm text-muted-foreground">No todos yet. Add your first one above.</p>
      ) : (
        <ul id="todo-list" className="mt-5 divide-y divide-border">
          {todos.map((todo) => (
            <li id={`todo-${todo.id}`} key={todo.id} aria-busy={(update.isPending && update.variables?.id === todo.id) || (remove.isPending && remove.variables === todo.id)} className="flex items-center gap-3 py-4">
              <Checkbox
                id={`todo-completed-${todo.id}`}
                checked={todo.completed}
                disabled={isPending}
                onCheckedChange={(completed) => {
                  resetErrors();
                  update.mutate({ id: todo.id, completed });
                }}
              />
              <FieldLabel htmlFor={`todo-completed-${todo.id}`} className={`min-w-0 flex-1 break-words ${todo.completed ? "text-muted-foreground line-through" : ""}`}>
                {todo.title}
              </FieldLabel>
              <Button
                id={`todo-delete-${todo.id}`}
                type="button"
                disabled={isPending}
                onClick={() => {
                  resetErrors();
                  remove.mutate(todo.id);
                }}
                aria-label={`Delete ${todo.title}`}
                variant="ghost"
                size="sm"
              >Delete</Button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
