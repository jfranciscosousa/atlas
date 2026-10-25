defmodule Atlas.Content.EntryField.CheckLabel do
  @moduledoc """
  A label is unique among the active fields of one kind in one campaign, ignoring case, and it
  must not equal a built-in field label of that kind. The change also sets `label_key`, the lower
  case label that the unique index uses. A restore checks the label again, because another field
  may have taken it while this one was archived.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Atlas.Content.{EntryField, EntrySpec}

  @impl true
  def change(changeset, _opts, _context) do
    label = Ash.Changeset.get_attribute(changeset, :label)

    cond do
      is_nil(label) ->
        changeset

      changeset.action.name == :restore or changeset.action_type == :create or
          Ash.Changeset.changing_attribute?(changeset, :label) ->
        key = key(label)

        changeset
        |> Ash.Changeset.force_change_attribute(:label_key, key)
        |> Ash.Changeset.before_action(&check(&1, key))

      true ->
        changeset
    end
  end

  @doc "The label in lower case, as the unique index holds it."
  def key(label), do: label |> String.trim() |> String.downcase()

  defp check(changeset, key) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)

    cond do
      key in Enum.map(EntrySpec.fields(kind), &String.downcase(&1.label)) ->
        error(changeset, "is already a built-in field of #{EntrySpec.fetch!(kind).label}")

      taken?(changeset, kind, key) ->
        error(changeset, "is already used by another field of this kind")

      true ->
        changeset
    end
  end

  defp taken?(changeset, kind, key) do
    campaign_id = Ash.Changeset.get_attribute(changeset, :campaign_id)

    query =
      Ash.Query.filter(
        EntryField,
        campaign_id == ^campaign_id and kind == ^kind and label_key == ^key and
          is_nil(archived_at)
      )

    # A new field has no ID yet.
    query =
      case changeset.data.id do
        nil -> query
        id -> Ash.Query.filter(query, id != ^id)
      end

    Ash.exists?(query, authorize?: false)
  end

  defp error(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :label, message: message)
end
