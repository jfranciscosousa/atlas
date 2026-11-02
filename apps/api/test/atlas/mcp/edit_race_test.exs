defmodule Atlas.Mcp.EditRaceTest do
  @moduledoc """
  An MCP edit is planned from the stored Yjs state and stored a moment later. In between, another
  writer can change the section's JSON with a plain save (an import or a restore). The stored
  state is then rebuilt, and the plan no longer fits it.

  The tests make the race certain: they plan an edit, change the section, then store the plan.
  The edit must fail as stale and leave the other writer's text, never crash or merge two
  unrelated histories.
  """
  use Atlas.DataCase, async: true

  alias Atlas.Fixtures
  alias Atlas.Mcp.EditBlocks
  alias Atlas.RichText.Collab

  setup do
    gm = Fixtures.user()
    campaign = Fixtures.campaign(gm)
    npc = Fixtures.entry(gm, campaign, "npc", "Vex")
    session = Ash.create!(Atlas.Campaigns.Session, %{campaign_id: campaign.id}, actor: gm)
    {:ok, gm: gm, npc: npc, session: session}
  end

  defp args(kind, id, section, text) do
    %{
      kind: kind,
      id: id,
      section: section,
      operations: [%{"op" => "insert", "blocks" => [%{"type" => "paragraph", "content" => text}]}],
      remove_images: false,
      delete_many: false
    }
  end

  defp plan!(ctx, kind, id, section, text) do
    assert {:ok, plan} = EditBlocks.plan(ctx.gm, args(kind, id, section, text))
    plan
  end

  defp other_writer!(resource, id, section, text, ctx) do
    Fixtures.save_section!(resource, id, section, [Fixtures.paragraph(text, "other")], ctx.gm)
  end

  defp texts(resource, id, section, ctx) do
    resource
    |> Ash.get!(id, actor: ctx.gm)
    |> Map.fetch!(Atlas.RichText.json_attribute(section))
    |> Enum.flat_map(& &1["content"])
    |> Enum.map(& &1["text"])
  end

  defp revision(resource, id, section, ctx) do
    resource
    |> Ash.get!(id, actor: ctx.gm)
    |> Map.fetch!(Atlas.RichText.revision_attribute(section))
  end

  test "a plan stored after another writer changed the section is stale", ctx do
    plan = plan!(ctx, "npc", ctx.npc.id, "description", "Mine")
    other_writer!(Atlas.Content.Entry, ctx.npc.id, :description, "Theirs", ctx)

    assert {:ok, :reset} =
             Collab.apply_update(plan.target, ctx.gm, plan.update,
               expected_revision: plan.expected_revision
             )

    assert {:error, :stale} = EditBlocks.settled(:reset)
    assert EditBlocks.error_text(:stale) =~ "changed since you read it"

    assert ["Theirs"] == texts(Atlas.Content.Entry, ctx.npc.id, :description, ctx)
  end

  test "a retry after the reset plans from the new text and stores", ctx do
    stale = plan!(ctx, "npc", ctx.npc.id, "description", "Mine")
    other_writer!(Atlas.Content.Entry, ctx.npc.id, :description, "Theirs", ctx)
    assert {:ok, :reset} = Collab.apply_update(stale.target, ctx.gm, stale.update, [])

    retry = plan!(ctx, "npc", ctx.npc.id, "description", "Mine")

    assert {:ok, {:changed, 2}} =
             Collab.apply_update(retry.target, ctx.gm, retry.update,
               expected_revision: retry.expected_revision
             )

    assert ["Theirs", "Mine"] == texts(Atlas.Content.Entry, ctx.npc.id, :description, ctx)
  end

  test "a batch with one stale plan stores none of its edits", ctx do
    # The npc section sorts before the session section, so it is stored first and then undone.
    session_plan = plan!(ctx, "session", ctx.session.id, "prep", "Session text")
    npc_plan = plan!(ctx, "npc", ctx.npc.id, "description", "Npc text")
    other_writer!(Atlas.Campaigns.Session, ctx.session.id, :prep, "Theirs", ctx)

    entries =
      Enum.map([session_plan, npc_plan], &{&1.target, &1.update, expected_revision: nil})

    # The error names the position in the list that the caller sent, not the order of storing.
    assert {:error, 0, :stale} = Collab.apply_updates(entries, ctx.gm)

    assert [] == texts(Atlas.Content.Entry, ctx.npc.id, :description, ctx)
    assert 0 == revision(Atlas.Content.Entry, ctx.npc.id, :description, ctx)
    assert ["Theirs"] == texts(Atlas.Campaigns.Session, ctx.session.id, :prep, ctx)
  end

  test "after an undone batch, the same edits stored again succeed", ctx do
    session_plan = plan!(ctx, "session", ctx.session.id, "prep", "Session text")
    npc_plan = plan!(ctx, "npc", ctx.npc.id, "description", "Npc text")
    other_writer!(Atlas.Campaigns.Session, ctx.session.id, :prep, "Theirs", ctx)

    entries = Enum.map([npc_plan, session_plan], &{&1.target, &1.update, []})
    assert {:error, 1, :stale} = Collab.apply_updates(entries, ctx.gm)

    fresh = plan!(ctx, "session", ctx.session.id, "prep", "Session text")

    entries = [{npc_plan.target, npc_plan.update, []}, {fresh.target, fresh.update, []}]
    assert {:ok, [{:changed, 1}, {:changed, 2}]} = Collab.apply_updates(entries, ctx.gm)

    assert ["Npc text"] == texts(Atlas.Content.Entry, ctx.npc.id, :description, ctx)

    assert ["Theirs", "Session text"] ==
             texts(Atlas.Campaigns.Session, ctx.session.id, :prep, ctx)
  end
end
