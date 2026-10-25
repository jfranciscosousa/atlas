defmodule Atlas.Content.Entry.FilterByCustomValue do
  @moduledoc """
  Keeps the entries whose custom field has one value (equality). The list action takes
  `custom_field_id` and `custom_field_value` together. The value is text, parsed by the type of the
  field: a number as "3", a boolean as "true", a select as one of its choices, an entry field as
  the ID of the entry. Text ignores case.

  The field must be an active field of the campaign that the actor may read. A player who names a
  GM-only field gets the same error as for a field that does not exist, so a filter can never
  show what a GM-only value is. Preview as player (`as_player`) reads fields as a player does.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  alias Atlas.Content.{Entry, EntryField}
  alias Atlas.Content.EntryField.Value

  @impl true
  def prepare(query, _opts, %{actor: actor}) do
    id = Ash.Query.get_argument(query, :custom_field_id)
    value = Ash.Query.get_argument(query, :custom_field_value)

    cond do
      is_nil(id) and is_nil(value) ->
        query

      is_nil(id) or is_nil(value) ->
        error(
          query,
          :custom_field_value,
          "needs custom_field_id and custom_field_value together"
        )

      true ->
        filter(query, actor, id, value)
    end
  end

  defp filter(query, actor, id, value) do
    campaign_id = Ash.Query.get_argument(query, :campaign_id)
    as_player? = Ash.Query.get_argument(query, :as_player)

    case Ash.get(EntryField, id, actor: actor, not_found_error?: false) do
      {:ok, %EntryField{campaign_id: ^campaign_id, archived_at: nil, gm_only: gm_only} = field}
      when not (gm_only and as_player?) ->
        parse(query, actor, field, value)

      _ ->
        error(query, :custom_field_id, "is not a custom field that you can read")
    end
  end

  defp parse(query, actor, field, value) do
    case Value.normalize(field, value) do
      {:set, parsed} ->
        if field.type == :entry and not readable?(actor, field, parsed),
          do: error(query, :custom_field_value, "is not an entry that you can read"),
          else: where(query, field, parsed)

      :clear ->
        error(query, :custom_field_value, "cannot be empty")

      {:error, message} ->
        error(query, :custom_field_value, message)
    end
  end

  defp readable?(actor, field, id) do
    kind = EntryField.target_kind(field)

    match?(
      {:ok, %Entry{kind: ^kind, campaign_id: campaign_id}} when campaign_id == field.campaign_id,
      Ash.get(Entry, id, actor: actor, not_found_error?: false)
    )
  end

  defp where(query, %{type: :text, id: id}, text) do
    text = String.downcase(text)
    Ash.Query.filter(query, fragment("lower(? ->> ?::text) = ?::text", custom_fields, ^id, ^text))
  end

  defp where(query, %{type: :number, id: id}, number) do
    number = Decimal.new(to_string(number))

    Ash.Query.filter(
      query,
      fragment("(? ->> ?::text)::numeric = ?::numeric", custom_fields, ^id, ^number)
    )
  end

  defp where(query, %{id: id}, value) do
    Ash.Query.filter(
      query,
      fragment("? ->> ?::text = ?::text", custom_fields, ^id, ^to_string(value))
    )
  end

  defp error(query, field, message),
    do: Ash.Query.add_error(query, field: field, message: message)
end
