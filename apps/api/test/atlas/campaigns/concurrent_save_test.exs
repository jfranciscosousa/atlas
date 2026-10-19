defmodule Atlas.Campaigns.ConcurrentSaveTest do
  # Needs real, committed rows and separate connections, so it bypasses the shared sandbox.
  use ExUnit.Case, async: false

  import Atlas.Fixtures

  alias Atlas.Campaigns.Campaign
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    Sandbox.mode(Atlas.Repo, :auto)
    gm = user()
    campaign = campaign(gm)

    on_exit(fn ->
      # Campaigns have no destroy action, so clean up with SQL.
      Atlas.Repo.query!("delete from campaigns where id = $1", [Ecto.UUID.dump!(campaign.id)])
      Atlas.Repo.query!("delete from users where id = $1", [Ecto.UUID.dump!(gm.id)])
      Sandbox.mode(Atlas.Repo, :manual)
    end)

    {:ok, gm: gm, campaign: campaign}
  end

  test "of two saves with the same expected_revision exactly one succeeds", ctx do
    parent = self()

    tasks =
      for text <- ["first", "second"] do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go ->
              ctx.campaign
              |> Ash.Changeset.for_update(
                :save_description,
                %{json: [paragraph(text)], schema_version: 1, expected_revision: 0},
                actor: ctx.gm
              )
              |> Ash.update()
          end
        end)
      end

    for _ <- tasks, do: assert_receive({:ready, _})
    for task <- tasks, do: send(task.pid, :go)
    results = Enum.map(tasks, &Task.await/1)

    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, _}] = Enum.filter(results, &match?({:error, _}, &1))

    stored = Ash.get!(Campaign, ctx.campaign.id, actor: ctx.gm)
    assert stored.description_revision == 1
    assert stored.description_json == winner.description_json
  end
end
