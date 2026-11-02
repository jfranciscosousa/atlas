defmodule Atlas.Mcp.Records do
  @moduledoc """
  Batch reads for the MCP tools that take many records in one call. Each function does one query
  for the whole batch, so the number of queries does not grow with the number of records.
  """
  require Ash.Query

  alias Atlas.Campaigns.{PlayerLog, Session}
  alias Atlas.RichText.Mentions

  @doc """
  Reads the records with these IDs as the actor, in one query: `%{id => record}`. The read
  policies and field policies decide, as for `Ash.get/3`. A record that does not exist and one that
  the actor may not read are both absent.
  """
  @spec fetch(module(), [String.t()], term(), list()) :: %{String.t() => struct()}
  def fetch(resource, ids, actor, load \\ []) do
    ids = Enum.uniq(ids)

    query =
      resource
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.load(load)

    case Ash.read(query, actor: actor) do
      {:ok, records} -> Map.new(records, &{&1.id, &1})
      {:error, _} -> %{}
    end
  end

  @doc """
  The campaign ID of each record, in the order of the records. A skill has none. The sessions of
  player logs are read in one query.
  """
  @spec campaign_ids([struct()]) :: [String.t() | nil]
  def campaign_ids(records) do
    session_ids = for %PlayerLog{session_id: id} <- records, do: id

    sessions =
      if session_ids == [],
        do: %{},
        else:
          Session
          |> Ash.Query.filter(id in ^Enum.uniq(session_ids))
          |> Ash.read!(authorize?: false)
          |> Map.new(&{&1.id, &1.campaign_id})

    Enum.map(records, fn
      %PlayerLog{session_id: id} -> Map.fetch!(sessions, id)
      record -> Atlas.Mcp.Describe.campaign_id(record)
    end)
  end

  @doc """
  The mention labels for many texts, as `%{campaign_id => labels}`. `entries` is a list of
  `{campaign_id, documents}`. Each campaign is looked up once, however many texts it has.
  """
  @spec labels([{String.t() | nil, [[map()]]}], term()) :: %{optional(String.t() | nil) => map()}
  def labels(entries, actor) do
    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {campaign_id, documents} ->
      {campaign_id, Mentions.labels(Enum.concat(documents), actor, campaign_id)}
    end)
  end
end
