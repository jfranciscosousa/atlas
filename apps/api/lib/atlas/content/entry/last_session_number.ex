defmodule Atlas.Content.Entry.LastSessionNumber do
  @moduledoc """
  The number of the latest session whose log mentions an entry.

  A session log and the player logs of a session count. Both are open to every member, so the
  answer is the same for the GM and for a player. Prep is GM-only and never counts.

  One query reads the mention keys that search already projects. It scans only the logs of the
  campaigns in the list, so the cost follows the number of sessions, not the number of entries.

  It is the `last_session_number` calculation of `Entry`. The `last_mentioned` sort of the list
  calls `by_entry/1` itself, because Ash cannot sort the database query by a calculation that has
  no SQL expression.
  """
  use Ash.Resource.Calculation

  @sql """
  SELECT m.campaign_id, k.key, max(m.number)
  FROM (
    SELECT s.campaign_id, s.number, ss.mention_keys
    FROM sessions s
    JOIN search_sections ss
      ON ss.kind = 'session' AND ss.section = 'log' AND ss.record_id = s.id
    WHERE s.campaign_id = ANY($1) AND ss.has_mentions
    UNION ALL
    SELECT s.campaign_id, s.number, ss.mention_keys
    FROM player_logs p
    JOIN sessions s ON s.id = p.session_id
    JOIN search_sections ss
      ON ss.kind = 'player_log' AND ss.section = 'body' AND ss.record_id = p.id
    WHERE s.campaign_id = ANY($1) AND ss.has_mentions
  ) m
  CROSS JOIN LATERAL unnest(m.mention_keys) AS k(key)
  GROUP BY m.campaign_id, k.key
  """

  @impl true
  def load(_query, _opts, _context), do: [:campaign_id, :kind]

  @impl true
  def calculate(entries, _opts, _context) do
    latest = by_entry(entries)
    Enum.map(entries, &Map.get(latest, &1.id))
  end

  @doc """
  Map of entry ID to the number of the latest session that mentions it. An entry that no log
  mentions has no key. The caller has already authorized the entries.
  """
  @spec by_entry([%{id: String.t(), kind: atom(), campaign_id: String.t()}]) ::
          %{String.t() => pos_integer()}
  def by_entry([]), do: %{}

  def by_entry(entries) do
    campaign_ids = entries |> Enum.map(&Ecto.UUID.dump!(&1.campaign_id)) |> Enum.uniq()
    %{rows: rows} = Ecto.Adapters.SQL.query!(Atlas.Repo, @sql, [campaign_ids])

    latest =
      Map.new(rows, fn [campaign_id, key, number] ->
        {{Ecto.UUID.load!(campaign_id), key}, number}
      end)

    for entry <- entries,
        number = Map.get(latest, {entry.campaign_id, "#{entry.kind}:#{entry.id}"}),
        into: %{},
        do: {entry.id, number}
  end
end
