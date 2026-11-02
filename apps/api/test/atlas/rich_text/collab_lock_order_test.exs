defmodule Atlas.RichText.CollabLockOrderTest do
  @moduledoc """
  `Collab.apply_updates/2` takes the lock of every section before it locks any row.

  Another writer takes the lock of one section, then the row of the record. A batch that took its
  section locks one by one would hold the row after its first section and wait for the second
  section, while the other writer waits for the row: a deadlock. A batch that takes all its section
  locks first waits before it holds any row, and the other writer finishes.

  The test makes that order certain with two real database connections, so it runs outside the
  SQL sandbox and commits its data. It removes the data afterwards.
  """
  use ExUnit.Case, async: false

  alias Atlas.Fixtures
  alias Atlas.Mcp.EditBlocks
  alias Atlas.RichText.Collab
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @sections ~w(description secret_notes)

  # Runs `fun` on a real connection that commits. The sandbox does not wrap it.
  defp committed(fun), do: Sandbox.unboxed_run(Atlas.Repo, fun)

  defp edit_args(entry, section) do
    %{
      kind: "npc",
      id: entry.id,
      section: section,
      operations: [%{"op" => "insert", "blocks" => [%{"type" => "paragraph", "content" => "x"}]}],
      remove_images: false,
      delete_many: false
    }
  end

  defp cleanup(gm, campaign, entry) do
    committed(fn ->
      id = Ecto.UUID.dump!(entry.id)

      for table <- ~w(rich_text_docs search_words search_sections) do
        SQL.query!(Atlas.Repo, "DELETE FROM #{table} WHERE record_id = $1", [id])
      end

      SQL.query!(Atlas.Repo, "DELETE FROM entries WHERE id = $1", [id])

      SQL.query!(Atlas.Repo, "DELETE FROM campaigns WHERE id = $1", [Ecto.UUID.dump!(campaign.id)])

      SQL.query!(Atlas.Repo, "DELETE FROM users WHERE id = $1", [Ecto.UUID.dump!(gm.id)])
    end)
  end

  # The test waits on the batch itself: `Task.yield/2` ends early only if the batch finished.
  defp wait_until_blocked(batch) do
    blocked? =
      committed(fn ->
        %{rows: [[count]]} =
          SQL.query!(Atlas.Repo, """
          SELECT count(*) FROM pg_locks
          WHERE locktype = 'advisory' AND NOT granted
            AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
          """)

        count > 0
      end)

    cond do
      blocked? -> :ok
      Task.yield(batch, 20) == nil -> wait_until_blocked(batch)
      true -> flunk("the batch finished before it waited for the lock")
    end
  end

  test "a batch waits for all its section locks before it locks a row" do
    {gm, campaign, entry, entries} =
      committed(fn ->
        gm = Fixtures.user()
        campaign = Fixtures.campaign(gm)
        entry = Fixtures.entry(gm, campaign, "npc", "Vex")

        entries =
          for section <- @sections do
            {:ok, plan} = EditBlocks.plan(gm, edit_args(entry, section))
            {plan.target, plan.update, []}
          end

        {gm, campaign, entry, entries}
      end)

    on_exit(fn -> cleanup(gm, campaign, entry) end)

    test_pid = self()
    secret_notes_key = "npc:#{entry.id}:secret_notes"

    # The other writer: it holds the lock of the second section, waits for the go, then locks the row.
    writer =
      Task.async(fn ->
        committed(fn ->
          Atlas.Repo.transaction(fn ->
            SQL.query!(
              Atlas.Repo,
              "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
              [secret_notes_key]
            )

            send(test_pid, :holding)

            receive do
              :go -> :ok
            after
              10_000 -> raise "the test did not send :go"
            end

            SQL.query!(Atlas.Repo, "SELECT id FROM entries WHERE id = $1 FOR UPDATE", [
              Ecto.UUID.dump!(entry.id)
            ])

            :wrote
          end)
        end)
      end)

    assert_receive :holding, 5_000

    batch = Task.async(fn -> committed(fn -> Collab.apply_updates(entries, gm) end) end)

    wait_until_blocked(batch)
    send(writer.pid, :go)

    # With one-by-one locks, the row lock of the batch and the section lock of the writer would
    # deadlock here, and the database would cancel one of the two.
    assert {:ok, :wrote} = Task.await(writer, 10_000)
    assert {:ok, [{:changed, 1}, {:changed, 1}]} = Task.await(batch, 10_000)
  end
end
