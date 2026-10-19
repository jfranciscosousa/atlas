defmodule Atlas.Campaigns.CampaignTest do
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Campaigns.Campaign

  defp save(campaign, actor, json, expected, version \\ 1) do
    campaign
    |> Ash.Changeset.for_update(
      :save_description,
      %{json: json, schema_version: version, expected_revision: expected},
      actor: actor
    )
    |> Ash.update()
  end

  setup do
    gm = user()
    {:ok, gm: gm, campaign: campaign(gm)}
  end

  test "creating a campaign makes the actor its GM with empty sections", %{gm: gm, campaign: c} do
    assert c.gm_id == gm.id
    assert c.description_json == []
    assert {c.description_revision, c.description_schema_version} == {0, 1}
    assert c.progress_rewards_revision == 0
  end

  test "a save round-trips the document losslessly and bumps only its own revision", ctx do
    doc = [
      %{
        "id" => "a",
        "type" => "paragraph",
        "props" => %{"textAlignment" => "left", "backgroundColor" => "default", "n" => nil},
        "content" => [%{"type" => "text", "text" => "héllo", "styles" => %{"bold" => true}}],
        "children" => [%{paragraph("kid") | "content" => []}]
      },
      %{"id" => "b", "type" => "divider", "props" => %{}, "children" => []}
    ]

    assert {:ok, saved} = save(ctx.campaign, ctx.gm, doc, 0)
    assert saved.description_revision == 1

    reloaded = Ash.get!(Campaign, ctx.campaign.id, actor: ctx.gm)
    assert reloaded.description_json == doc
    assert reloaded.description_revision == 1
    assert reloaded.progress_rewards_revision == 0
  end

  test "a stale expected_revision is rejected even when the server loaded the latest record",
       ctx do
    assert {:ok, _} = save(ctx.campaign, ctx.gm, [paragraph("one")], 0)

    latest = Ash.get!(Campaign, ctx.campaign.id, actor: ctx.gm)
    assert latest.description_revision == 1
    assert {:error, error} = save(latest, ctx.gm, [paragraph("stale")], 0)
    assert Exception.message(error) =~ "stale" or Exception.message(error) =~ "Stale"

    assert Ash.get!(Campaign, ctx.campaign.id, actor: ctx.gm).description_json == [
             paragraph("one")
           ]

    # Identical content must not turn a stale save into a silent no-op success.
    assert {:error, _} = save(latest, ctx.gm, [paragraph("one")], 0)
  end

  test "an unsupported schema version fails without a partial write", ctx do
    assert {:error, _} = save(ctx.campaign, ctx.gm, [paragraph("x")], 0, 2)

    unchanged = Ash.get!(Campaign, ctx.campaign.id, actor: ctx.gm)
    assert {unchanged.description_json, unchanged.description_revision} == {[], 0}
  end

  test "an invalid document fails without a partial write", ctx do
    assert {:error, _} = save(ctx.campaign, ctx.gm, [%{paragraph("x") | "type" => "video"}], 0)
    assert Ash.get!(Campaign, ctx.campaign.id, actor: ctx.gm).description_revision == 0
  end

  test "section columns cannot be set through create or the other section's save", ctx do
    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(Campaign, %{name: "x", description_revision: 5}, actor: ctx.gm)
    end

    {:ok, saved} = save(ctx.campaign, ctx.gm, [paragraph("d")], 0)
    assert saved.progress_rewards_json == []
  end
end
