defmodule Atlas.FakeReqLLM do
  @moduledoc false

  # Replaces ReqLLM in tests. It sends the prompt to the calling process and returns a fixed draft and, for a prompt that says CONFLICT, a conflict.
  def generate_object(_model, context, _schema, _opts) do
    prompt = Enum.map_join(context.messages, "\n", &message_text/1)
    send(self(), {:llm_prompt, prompt})

    # Like ReqLLM without an API key.
    if prompt =~ "NO KEY",
      do:
        raise(
          Ash.Error.Invalid.exception(
            errors: [Ash.Error.Unknown.UnknownError.exception(error: "no key")]
          )
        )

    conflicts = if prompt =~ "CONFLICT", do: ["Ann and the GM disagree."], else: []

    {:ok,
     %{object: %{"result" => %{"draft" => "# Draft\n\nThe party won.", "conflicts" => conflicts}}}}
  end

  defp message_text(%{content: parts}), do: Enum.map_join(parts, &(Map.get(&1, :text) || ""))
end
