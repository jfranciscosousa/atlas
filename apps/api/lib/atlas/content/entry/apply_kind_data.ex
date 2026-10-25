defmodule Atlas.Content.Entry.ApplyKindData do
  @moduledoc """
  Applies the spec of the entry's kind (`Atlas.Content.EntrySpec`) to a create or an update:

    * A new entry starts with the default status of its kind. Any status must belong to the kind.
    * The fields must be fields of the kind, as text. A create stores them without blanks.
      An update merges them into the stored fields, and a blank value clears that field.
  """
  use Ash.Resource.Change

  alias Atlas.Content.EntrySpec

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :kind) do
      nil ->
        changeset

      kind ->
        changeset
        |> status(kind)
        |> fields(kind)
    end
  end

  # A create takes the status as an argument, so it may be left out. An update changes the attribute.
  defp status(changeset, kind) do
    status =
      if changeset.action_type == :create,
        do: Ash.Changeset.get_argument(changeset, :status),
        else: Ash.Changeset.get_attribute(changeset, :status)

    cond do
      is_nil(status) and changeset.action_type == :create ->
        Ash.Changeset.force_change_attribute(changeset, :status, EntrySpec.default_status(kind))

      is_nil(status) ->
        changeset

      status in EntrySpec.statuses(kind) ->
        Ash.Changeset.force_change_attribute(changeset, :status, status)

      true ->
        statuses = kind |> EntrySpec.statuses() |> Enum.join(", ")

        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "must be one of #{statuses} for #{EntrySpec.fetch!(kind).label}"
        )
    end
  end

  defp fields(changeset, kind) do
    if changeset.action_type == :create or Ash.Changeset.changing_attribute?(changeset, :fields) do
      given = Ash.Changeset.get_attribute(changeset, :fields)

      case EntrySpec.normalize_fields(kind, given) do
        {:ok, normalized} ->
          Ash.Changeset.force_change_attribute(
            changeset,
            :fields,
            merge(changeset, given, normalized)
          )

        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :fields, message: message)
      end
    else
      changeset
    end
  end

  defp merge(%{action_type: :create}, _given, normalized), do: normalized

  defp merge(%{data: data}, given, normalized) do
    cleared = for {key, value} <- given || %{}, blank?(value), do: to_string(key)
    data.fields |> Map.merge(normalized) |> Map.drop(cleared)
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
