defmodule Atlas.AudienceTest do
  @moduledoc """
  The audience of each section, and the proof that the app and MCP name it the same way.

  MCP gives the audience next to the text. The app shows it as a badge next to the section title.
  `apps/web/src/lib/audience.ts` repeats the labels and the fixed audiences. A difference is a bug.
  """
  use ExUnit.Case, async: true

  alias Atlas.Audience
  alias Atlas.Kinds

  @web_file Path.expand("../../../web/src/lib/audience.ts", __DIR__)

  @states %{
    hidden: %{hidden: true, archived_at: nil},
    archived: %{hidden: false, archived_at: ~U[2026-01-01 00:00:00Z]},
    shown: %{hidden: false, archived_at: nil}
  }

  test "every section of every kind has an audience, so a new section cannot ship without one" do
    for kind <- Kinds.kinds(), section <- Kinds.sections(kind) do
      state = Map.merge(%{visibility: :everyone}, @states.shown)

      assert Audience.of(kind, section, state) in Audience.all(),
             "#{kind}:#{section} has no audience"
    end
  end

  test "the secret sections are for the GM alone" do
    assert Audience.of(:session, :prep) == :gm_only
    assert Audience.of(:character, :secret_notes) == :gm_only

    for kind <- Atlas.Content.EntrySpec.kinds(),
        state <- Map.values(@states),
        do: assert(Audience.of(kind, :secret_notes, state) == :gm_only)
  end

  test "a world entry description is for the GM alone until the GM shows the entry" do
    for kind <- Atlas.Content.EntrySpec.kinds() do
      assert Audience.of(kind, :description, @states.hidden) == :gm_only
      assert Audience.of(kind, :description, @states.archived) == :gm_only
      assert Audience.of(kind, :description, @states.shown) == :everyone
    end
  end

  test "a note body has the visibility of the note" do
    for visibility <- [:only_me, :me_and_gm, :character, :everyone],
        do: assert(Audience.of(:note, :body, %{visibility: visibility}) == visibility)
  end

  test "members read the campaign, the log, the character and the player logs" do
    assert Audience.of(:campaign, :description) == :everyone
    assert Audience.of(:campaign, :progress_rewards) == :everyone
    assert Audience.of(:session, :log) == :everyone
    assert Audience.of(:character, :description) == :everyone
    assert Audience.of(:player_log, :body) == :everyone
    assert Audience.of(:skill, :body) == :only_me
  end

  test "an unknown section has no audience, and so no default" do
    for args <- [[:session, :notes, %{}], [:npc, :description, %{}]],
        do: assert_raise(FunctionClauseError, fn -> apply(Audience, :of, args) end)
  end

  test "only the audiences that include a player count as read by players" do
    assert Enum.filter(Audience.all(), &Audience.players_read?/1) == [:character, :everyone]
  end

  describe "the app" do
    setup do
      {:ok, source: File.read!(@web_file)}
    end

    test "labels each audience as MCP does", %{source: source} do
      assert web_table(source, "AUDIENCE_LABELS") ==
               Map.new(Audience.labels(), fn {audience, label} -> {to_string(audience), label} end)
    end

    test "has the fixed audience of each section as MCP does", %{source: source} do
      # A note body and a world entry description depend on the record: the app computes them.
      fixed =
        for kind <- Kinds.kinds() -- [:note | Atlas.Content.EntrySpec.kinds()],
            section <- Kinds.sections(kind),
            into: %{} do
          {"#{kind}:#{section}", to_string(Audience.of(kind, section))}
        end

      assert web_table(source, "FIXED_AUDIENCE") == fixed
    end
  end

  # The entries of a table in audience.ts, as `%{key => value}`.
  defp web_table(source, name) do
    [_, body] = Regex.run(~r/export const #{name}[^{]*\{(.*?)\n\};/s, source)

    ~r/^\s*"?([\w:]+)"?:\s*"([^"]+)",?$/m
    |> Regex.scan(body, capture: :all_but_first)
    |> Map.new(fn [key, value] -> {key, value} end)
  end
end
