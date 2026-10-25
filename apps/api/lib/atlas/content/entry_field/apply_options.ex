defmodule Atlas.Content.EntryField.ApplyOptions do
  @moduledoc """
  Sets `options` from the arguments, by the type of the field:

    * A select takes `choices`: 1 to 50 different names, ignoring case, of 1 to 60 characters.
    * An entry field takes `target_kind`: the kind of entry it points to.
    * A text, number or boolean field takes neither.

  The type and the target kind never change. An update may change the choices of a select.
  `renamed_choices` maps an old choice to its new name. The stored values of the entries follow the
  rename. A choice that is gone from the list and that entries use is refused: the values would
  otherwise point to nothing. The GM renames the choice, or changes those entries first.
  """
  use Ash.Resource.Change

  alias Atlas.Content.EntryField

  @max_choices 50
  @max_length 60

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.action_type == :create, do: create(changeset), else: update(changeset)
  end

  defp create(changeset) do
    type = Ash.Changeset.get_attribute(changeset, :type)
    choices = Ash.Changeset.get_argument(changeset, :choices)
    target = Ash.Changeset.get_argument(changeset, :target_kind)

    case {type, choices, target} do
      {:select, nil, _} ->
        error(changeset, :choices, "are needed for a select field")

      {:select, _, kind} when not is_nil(kind) ->
        error(changeset, :target_kind, "is only for a field that links to an entry")

      {:select, choices, nil} ->
        with_choices(changeset, choices, fn choices ->
          Ash.Changeset.force_change_attribute(changeset, :options, %{"choices" => choices})
        end)

      {:entry, _, nil} ->
        error(changeset, :target_kind, "is needed for a field that links to an entry")

      {:entry, choices, _} when not is_nil(choices) ->
        error(changeset, :choices, "are only for a select field")

      {:entry, nil, kind} ->
        Ash.Changeset.force_change_attribute(changeset, :options, %{
          "target_kind" => Atom.to_string(kind)
        })

      {_, nil, nil} ->
        Ash.Changeset.force_change_attribute(changeset, :options, %{})

      {_, nil, _} ->
        error(changeset, :target_kind, "is only for a field that links to an entry")

      {_, _, _} ->
        error(changeset, :choices, "are only for a select field")
    end
  end

  defp update(changeset) do
    choices = Ash.Changeset.get_argument(changeset, :choices)
    renamed = Ash.Changeset.get_argument(changeset, :renamed_choices)
    field = changeset.data

    cond do
      is_nil(choices) and is_nil(renamed) ->
        changeset

      field.type != :select ->
        error(changeset, :choices, "are only for a select field")

      is_nil(choices) ->
        error(changeset, :renamed_choices, "need the new list of choices")

      true ->
        with_choices(changeset, choices, &change_choices(changeset, &1, renamed || %{}))
    end
  end

  defp change_choices(changeset, choices, renamed) do
    old = EntryField.choices(changeset.data)
    renames = Map.new(renamed, fn {from, to} -> {to_string(from), String.trim(to_string(to))} end)

    cond do
      Enum.any?(Map.keys(renames), &(&1 not in old)) ->
        error(changeset, :renamed_choices, "can only rename a choice that exists")

      Enum.any?(renames, fn {from, to} -> from in choices or to not in choices end) ->
        error(
          changeset,
          :renamed_choices,
          "must give the old name that is gone, and a new name that is in the choices"
        )

      true ->
        changeset
        |> Ash.Changeset.force_change_attribute(:options, %{"choices" => choices})
        |> Ash.Changeset.before_action(&refuse_used(&1, (old -- choices) -- Map.keys(renames)))
        |> Ash.Changeset.after_action(fn _changeset, field ->
          rewrite(field, renames)
          {:ok, field}
        end)
    end
  end

  # Removing a choice that entries use would leave values that point to nothing.
  defp refuse_used(changeset, []), do: changeset

  defp refuse_used(changeset, removed) do
    field = changeset.data

    used =
      Enum.find_value(removed, fn choice ->
        case usage(field, choice) do
          0 -> nil
          count -> {choice, count}
        end
      end)

    case used do
      nil ->
        changeset

      {choice, count} ->
        error(
          changeset,
          :choices,
          "cannot drop \"#{choice}\": #{count} #{if count == 1, do: "entry uses", else: "entries use"} it. Rename it, or change those entries first"
        )
    end
  end

  defp usage(field, choice) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        Atlas.Repo,
        "SELECT count(*) FROM entries WHERE campaign_id = $1 AND kind = $2 AND custom_fields ->> $3 = $4",
        [
          Ecto.UUID.dump!(field.campaign_id),
          Atom.to_string(field.kind),
          field.id,
          choice
        ]
      )

    count
  end

  # One statement reads every old value before it writes, so a chain of renames (a to b, b to c)
  # cannot apply twice.
  defp rewrite(_field, renames) when map_size(renames) == 0, do: :ok

  defp rewrite(field, renames) do
    {from, to} = renames |> Map.to_list() |> Enum.unzip()

    Ecto.Adapters.SQL.query!(
      Atlas.Repo,
      """
      UPDATE entries e
      SET custom_fields = jsonb_set(e.custom_fields, ARRAY[$3::text], to_jsonb(m.new_value))
      FROM unnest($4::text[], $5::text[]) AS m(old_value, new_value)
      WHERE e.campaign_id = $1 AND e.kind = $2 AND e.custom_fields ->> $3 = m.old_value
      """,
      [Ecto.UUID.dump!(field.campaign_id), Atom.to_string(field.kind), field.id, from, to]
    )
  end

  defp with_choices(changeset, choices, fun) do
    cleaned = Enum.map(choices, &String.trim/1)
    keys = Enum.map(cleaned, &String.downcase/1)

    cond do
      cleaned == [] ->
        error(changeset, :choices, "need at least one choice")

      length(cleaned) > @max_choices ->
        error(changeset, :choices, "can have at most #{@max_choices} choices")

      Enum.any?(cleaned, &(&1 == "" or String.length(&1) > @max_length)) ->
        error(changeset, :choices, "must have 1 to #{@max_length} characters each")

      length(Enum.uniq(keys)) != length(keys) ->
        error(changeset, :choices, "must be different, ignoring case")

      true ->
        fun.(cleaned)
    end
  end

  defp error(changeset, field, message),
    do: Ash.Changeset.add_error(changeset, field: field, message: message)
end
