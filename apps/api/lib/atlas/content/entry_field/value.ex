defmodule Atlas.Content.EntryField.Value do
  @moduledoc """
  The value of a custom field on one entry. It checks and converts a value by the type of its
  field. A value is stored as JSON in `entries.custom_fields`, under the ID of the field:

    * text: a trimmed string of at most 500 characters
    * number: an integer or a float, never infinite
    * boolean: `true` or `false`
    * select: one of the choices of the field
    * entry: the ID of an entry. `Atlas.Content.Entry.ApplyCustomValues` checks the entry itself.

  An empty value clears the field: `nil`, or a blank string. `false` and `0` are values.
  A client may send a number or a boolean as text; the filter of a list always does.
  """

  alias Atlas.Content.EntryField

  @text_max 500
  @number_max 1.0e15

  @doc "The longest text of a text field."
  def text_max, do: @text_max

  @doc """
  Checks `raw` for `field`. Returns `:clear` for an empty value, `{:set, value}`, or `{:error, message}`.
  """
  @spec normalize(map(), term()) :: :clear | {:set, term()} | {:error, String.t()}
  def normalize(_field, nil), do: :clear

  def normalize(field, raw) when is_binary(raw) do
    case String.trim(raw) do
      "" -> :clear
      text -> from_text(field, text)
    end
  end

  def normalize(%{type: :number}, raw) when is_number(raw), do: number(raw)
  def normalize(%{type: :boolean}, raw) when is_boolean(raw), do: {:set, raw}
  def normalize(field, _raw), do: {:error, "#{field.label} must be #{article(field.type)}"}

  defp from_text(%{type: :text}, text) do
    if String.length(text) <= @text_max,
      do: {:set, text},
      else: {:error, "is longer than #{@text_max} characters"}
  end

  defp from_text(%{type: :number} = field, text) do
    case parse_number(text) do
      {:ok, number} -> number(number)
      :error -> {:error, "#{field.label} must be a number"}
    end
  end

  defp from_text(%{type: :boolean}, "true"), do: {:set, true}
  defp from_text(%{type: :boolean}, "false"), do: {:set, false}

  defp from_text(%{type: :boolean} = field, _),
    do: {:error, "#{field.label} must be true or false"}

  defp from_text(%{type: :select} = field, text) do
    choices = EntryField.choices(field)

    if text in choices,
      do: {:set, text},
      else: {:error, "#{field.label} must be one of: #{Enum.join(choices, ", ")}"}
  end

  defp from_text(%{type: :entry} = field, text) do
    case Ecto.UUID.cast(text) do
      {:ok, id} -> {:set, id}
      :error -> {:error, "#{field.label} must be the ID of an entry"}
    end
  end

  defp number(number) when abs(number) <= @number_max, do: {:set, number}
  defp number(_), do: {:error, "is too large"}

  defp parse_number(text) do
    case Integer.parse(text) do
      {integer, ""} ->
        {:ok, integer}

      _ ->
        case Float.parse(text) do
          {float, ""} -> {:ok, float}
          _ -> :error
        end
    end
  end

  defp article(:text), do: "text"
  defp article(:number), do: "a number"
  defp article(:boolean), do: "true or false"
  defp article(:select), do: "one of its choices"
  defp article(:entry), do: "the ID of an entry"
end
