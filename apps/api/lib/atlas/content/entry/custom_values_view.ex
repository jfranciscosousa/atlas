defmodule Atlas.Content.Entry.CustomValuesView do
  @moduledoc """
  The custom fields of an entry, with their values, as one actor may read them. The app and the MCP
  tools both read this calculation, so they show the same.

  The result has one item for each active custom field of the entry's kind that the actor may read,
  in order, with `nil` for a field that has no value. The read policy of `Atlas.Content.EntryField`
  decides which fields the actor gets: a player never gets a GM-only field, nor its value. An
  archived field is left out, and its stored value with it.

  The value of an entry field is `nil` or a map with the `kind`, the `id`, the `label` and two flags.
  An entry that the actor cannot read is `restricted`: it has the label "Restricted entry" and no
  ID, as a mention has. An archived entry that the actor may read (only the GM) has the label
  "Deleted entry". `shown` is true when players read the entry, so Preview as player can restrict it.
  """
  use Ash.Resource.Calculation

  require Ash.Query

  alias Atlas.Content.{Entry, EntryField}

  @impl true
  def load(_query, _opts, _context), do: [:campaign_id, :kind, :custom_fields]

  @impl true
  def calculate(records, _opts, context) do
    campaign_ids = records |> Enum.map(& &1.campaign_id) |> Enum.uniq()

    fields =
      EntryField
      |> Ash.Query.filter(campaign_id in ^campaign_ids and is_nil(archived_at))
      |> Ash.Query.sort(position: :asc, inserted_at: :asc, id: :asc)
      |> Ash.read!(actor: context.actor)
      |> Enum.group_by(&{&1.campaign_id, &1.kind})

    targets = targets(records, fields, campaign_ids, context.actor)

    Enum.map(records, fn record ->
      fields
      |> Map.get({record.campaign_id, record.kind}, [])
      |> Enum.map(&view(&1, Map.get(record.custom_fields, &1.id), targets))
    end)
  end

  defp targets(records, fields, campaign_ids, actor) do
    ids =
      for record <- records,
          field <- Map.get(fields, {record.campaign_id, record.kind}, []),
          field.type == :entry,
          id = Map.get(record.custom_fields, field.id),
          uniq: true,
          do: id

    if ids == [] do
      %{}
    else
      Entry
      |> Ash.Query.filter(id in ^ids and campaign_id in ^campaign_ids)
      |> Ash.read!(actor: actor)
      |> Map.new(&{&1.id, &1})
    end
  end

  defp view(field, value, targets) do
    %{
      id: field.id,
      label: field.label,
      type: Atom.to_string(field.type),
      gm_only: field.gm_only,
      position: field.position,
      choices: if(field.type == :select, do: EntryField.choices(field)),
      target_kind: if(field.type == :entry, do: field.options["target_kind"]),
      value: value(field, value, targets)
    }
  end

  defp value(%{type: :entry} = field, id, targets) when is_binary(id) do
    kind = field.options["target_kind"]
    target_atom = EntryField.target_kind(field)

    case Map.get(targets, id) do
      %Entry{kind: target_kind} = target when target_kind == target_atom ->
        shown = target.hidden == false and is_nil(target.archived_at)

        %{
          kind: kind,
          id: target.id,
          label: if(is_nil(target.archived_at), do: target.name, else: "Deleted entry"),
          restricted: false,
          shown: shown
        }

      _ ->
        %{kind: kind, id: nil, label: "Restricted entry", restricted: true, shown: false}
    end
  end

  defp value(_field, value, _targets), do: value
end
