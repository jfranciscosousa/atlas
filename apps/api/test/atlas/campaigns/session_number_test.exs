defmodule Atlas.Campaigns.SessionNumberTest do
  # Needs real, committed rows and separate connections, so it bypasses the shared sandbox.
  use ExUnit.Case, async: false

  import Atlas.Fixtures

  alias Atlas.Campaigns.Session
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    Sandbox.mode(Atlas.Repo, :auto)
    gm = user()
    campaign = campaign(gm)

    on_exit(fn ->
      id = Ecto.UUID.dump!(campaign.id)
      Atlas.Repo.query!("delete from sessions where campaign_id = $1", [id])
      Atlas.Repo.query!("delete from campaigns where id = $1", [id])
      Atlas.Repo.query!("delete from users where id = $1", [Ecto.UUID.dump!(gm.id)])
      Sandbox.mode(Atlas.Repo, :manual)
    end)

    {:ok, gm: gm, campaign: campaign}
  end

  test "creates at the same time never take the same number", ctx do
    numbers =
      1..8
      |> Task.async_stream(
        fn _ -> Ash.create!(Session, %{campaign_id: ctx.campaign.id}, actor: ctx.gm).number end,
        max_concurrency: 8,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, number} -> number end)

    assert Enum.sort(numbers) == Enum.to_list(1..8)
  end
end
