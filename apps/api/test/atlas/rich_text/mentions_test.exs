defmodule Atlas.RichText.MentionsTest do
  use Atlas.DataCase, async: true

  import Atlas.Fixtures

  alias Atlas.Campaigns.{Campaign, Character, Invitation, Session}
  alias Atlas.Content.Note

  defp mention(kind, id), do: %{"type" => "mention", "props" => %{"kind" => kind, "id" => id}}

  defp text(text), do: %{"type" => "text", "text" => text, "styles" => %{}}

  defp read_as(campaign, actor) do
    Campaign
    |> Ash.ActionInput.for_action(:describe, %{id: campaign.id}, actor: actor)
    |> Ash.run_action!()
  end

  setup do
    gm = user()
    player = user()
    campaign = campaign(gm)
    invitation = Ash.create!(Invitation, %{campaign_id: campaign.id}, actor: gm)
    Ash.create!(Character, %{token: invitation.token}, action: :join, actor: player)

    session = Ash.create!(Session, %{campaign_id: campaign.id}, actor: gm)
    Ash.update!(session, %{title: "The Keep"}, action: :update_details, actor: gm)

    hidden = Ash.create!(Note, %{campaign_id: campaign.id, title: "Secret plot"}, actor: gm)
    shown = Ash.create!(Note, %{campaign_id: campaign.id, title: "Handout"}, actor: gm)
    Ash.update!(shown, %{visibility: :everyone}, action: :set_visibility, actor: gm)

    archived = Ash.create!(Note, %{campaign_id: campaign.id, title: "Old idea"}, actor: gm)
    archived = Ash.update!(archived, %{visibility: :everyone}, action: :set_visibility, actor: gm)
    Ash.update!(archived, %{}, action: :archive, actor: gm)

    # The GM may read this note, but it belongs to another campaign. The editor lists one
    # campaign only, so it shows "Restricted entry" and MCP must show the same.
    elsewhere =
      Ash.create!(Note, %{campaign_id: campaign(gm, "Other").id, title: "Other campaign"},
        actor: gm
      )

    character = campaign |> Ash.load!(:characters, authorize?: false) |> Map.fetch!(:characters)

    refs =
      [
        mention("session", session.id),
        mention("note", hidden.id),
        mention("note", shown.id),
        mention("note", archived.id),
        mention("character", hd(character).id),
        mention("note", Ash.UUID.generate()),
        mention("note", elsewhere.id)
      ]

    save_section!(
      Campaign,
      campaign.id,
      :description,
      [
        %{
          "id" => "p1",
          "type" => "paragraph",
          "props" => %{},
          "content" => Enum.intersperse(refs, text(" | ")),
          "children" => []
        }
      ],
      gm
    )

    {:ok, gm: gm, player: player, campaign: campaign, session: session, hidden: hidden}
  end

  # The mentions of the first block, as `%{"kind", "id", "label"}`.
  defp mentions(blocks) do
    for %{"type" => "mention", "props" => props} <- hd(blocks)["content"], do: props
  end

  test "the GM reads every name, and an archived note is a deleted entry", ctx do
    %{description: blocks} = read_as(ctx.campaign, ctx.gm)
    mentions = mentions(blocks)

    assert %{"label" => "Session 1: The Keep"} =
             Enum.find(mentions, &(&1["id"] == ctx.session.id))

    assert %{"label" => "Secret plot"} = Enum.find(mentions, &(&1["id"] == ctx.hidden.id))

    labels = Enum.map(mentions, & &1["label"])
    assert "Handout" in labels
    assert "Deleted entry" in labels
    assert "Unnamed character" in labels
    refute "Other campaign" in labels
  end

  test "a player gets no name for a hidden note, an archived note or an unknown entry", ctx do
    %{description: blocks} = read_as(ctx.campaign, ctx.player)
    mentions = mentions(blocks)
    labels = Enum.map(mentions, & &1["label"])

    assert "Session 1: The Keep" in labels
    assert "Handout" in labels
    assert "Unnamed character" in labels
    refute "Secret plot" in labels
    refute "Old idea" in labels
    refute "Deleted entry" in labels
    # The hidden note, the archived note, the unknown ID and the other campaign's note.
    assert Enum.count(labels, &(&1 == "Restricted entry")) == 4
    # The ID stays, so a client that writes the block back keeps the mention.
    assert Enum.any?(mentions, &(&1["id"] == ctx.hidden.id))
  end
end
