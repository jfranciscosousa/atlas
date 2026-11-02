defmodule Atlas.Content.EntrySurfaceCoverageTest do
  @moduledoc """
  Every public path on `Entry` needs a player-view test.

  A player must never reach a hidden or archived entry, or its secret notes. A new path skips the
  tests in `entry_test.exs`, `entry_surfaces_test.exs` and `entry_rpc_test.exs` unless someone
  writes one. This test fails when a path is exposed and not registered below.

  To fix a failure, write the player-view test: read as a player and assert the path returns no
  hidden entry, no archived entry and no secret notes. Then add the path here with the name of that
  test. Name a real test; a false name defeats the purpose.

  Other hidden resources need their own copy of this test when they expose new paths.
  """
  use ExUnit.Case, async: true

  alias Atlas.Content.Entry

  # Each exposed path and the player-view test that covers it.
  @rpc_actions %{
    create_entry: "entry_rpc_test.exs: a player cannot write, a non-member reads nothing",
    rename_entry: "entry_rpc_test.exs: a player cannot write, a non-member reads nothing",
    set_entry_hidden: "entry_rpc_test.exs: a player cannot write, a non-member reads nothing",
    archive_entry: "entry_rpc_test.exs: a player cannot write, a non-member reads nothing",
    restore_entry: "entry_rpc_test.exs: a player cannot write, a non-member reads nothing",
    list_entries: "entry_rpc_test.exs: list and get show the same to the player",
    get_entry: "entry_rpc_test.exs: a player cannot read a hidden or archived entry by ID"
  }

  # Each MCP tool that runs an action of Entry. The tools on other resources that read entries,
  # such as `get_many` and `read_blocks_many`, have their player-view tests in `mcp_batch_test.exs`.
  @mcp_tools %{
    list_entries: "mcp_entries_test.exs: never see a hidden entry",
    get_entry: "mcp_entries_test.exs: never see a hidden entry",
    create_entry: "mcp_entries_test.exs: cannot create, change, show, archive or restore",
    rename_entry: "mcp_entries_test.exs: cannot create, change, show, archive or restore",
    set_entry_hidden: "mcp_entries_test.exs: cannot create, change, show, archive or restore",
    archive_entry: "mcp_entries_test.exs: cannot create, change, show, archive or restore",
    restore_entry: "mcp_entries_test.exs: cannot create, change, show, archive or restore",
    set_entries_hidden:
      "mcp_batch_test.exs: a player changes nothing, and cannot tell a hidden entry from a missing one",
    archive_entries:
      "mcp_batch_test.exs: a player changes nothing, and cannot tell a hidden entry from a missing one",
    restore_entries:
      "mcp_batch_test.exs: a player changes nothing, and cannot tell a hidden entry from a missing one"
  }

  @relationships %{
    campaign: "entry_test.exs: a player reads the campaign of a shown entry"
  }

  @aggregates %{}

  test "every exposed RPC action on Entry has a player-view test" do
    assert_covered(:rpc_actions, exposed_rpc_actions(), @rpc_actions)
  end

  test "every MCP tool on Entry has a player-view test" do
    assert_covered(:mcp_tools, exposed_mcp_tools(), @mcp_tools)
  end

  test "every exposed aggregate on Entry has a player-view test" do
    assert_covered(:aggregates, exposed_aggregates(), @aggregates)
  end

  test "every exposed relationship on Entry has a player-view test" do
    assert_covered(:relationships, exposed_relationships(), @relationships)
  end

  defp assert_covered(kind, exposed, registered) do
    uncovered = exposed -- Map.keys(registered)
    stale = Map.keys(registered) -- exposed

    assert uncovered == [],
           """
           New #{kind} on Entry have no player-view test: #{inspect(uncovered)}.

           Write a test that reads as a player and asserts the path returns no hidden entry,
           no archived entry and no secret notes. Then add the path to @#{kind} in this file
           with the name of that test.
           """

    assert stale == [],
           """
           @#{kind} names paths that Entry no longer exposes: #{inspect(stale)}.
           Remove them from this file.
           """
  end

  defp exposed_rpc_actions do
    Atlas.Content
    |> AshTypescript.Rpc.Info.typescript_rpc()
    |> Enum.find(&(&1.resource == Entry))
    |> case do
      nil -> []
      config -> config.rpc_actions |> Enum.map(& &1.name) |> Enum.sort()
    end
  end

  defp exposed_mcp_tools do
    Atlas.Content
    |> Spark.Dsl.Extension.get_entities([:tools])
    |> Enum.filter(&(&1.resource == Entry))
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp exposed_aggregates do
    Entry |> Ash.Resource.Info.public_aggregates() |> Enum.map(& &1.name) |> Enum.sort()
  end

  defp exposed_relationships do
    Entry |> Ash.Resource.Info.public_relationships() |> Enum.map(& &1.name) |> Enum.sort()
  end
end
