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

  test "the GM reads every name, and an archived note is a deleted entry", ctx do
    %{description: text} = read_as(ctx.campaign, ctx.gm)

    assert text =~ "[@Session 1: The Keep](atlas-entry:session:#{ctx.session.id})"
    assert text =~ "[@Secret plot](atlas-entry:note:#{ctx.hidden.id})"
    assert text =~ "[@Handout]("
    assert text =~ "[@Deleted entry]("
    assert text =~ "[@Unnamed character]("
    refute text =~ "Other campaign"
  end

  test "a player gets no name for a hidden note, an archived note or an unknown entry", ctx do
    %{description: text} = read_as(ctx.campaign, ctx.player)

    assert text =~ "[@Session 1: The Keep]("
    assert text =~ "[@Handout]("
    assert text =~ "[@Unnamed character]("
    refute text =~ "Secret plot"
    refute text =~ "Old idea"
    refute text =~ "Deleted entry"
    # The hidden note, the archived note, the unknown ID and the other campaign's note.
    assert length(String.split(text, "[@Restricted entry](")) == 5
    # The ID stays, so a model that writes the text back keeps the mention.
    assert text =~ "atlas-entry:note:#{ctx.hidden.id}"
  end
end
