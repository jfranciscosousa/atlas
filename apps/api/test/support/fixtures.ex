defmodule Atlas.Fixtures do
  @moduledoc false

  def user(email \\ "gm#{System.unique_integer([:positive])}@example.com") do
    Ash.create!(
      Atlas.Accounts.User,
      %{
        email: email,
        display_name: "Test User",
        password: "a-secure-password",
        password_confirmation: "a-secure-password"
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  def campaign(gm, name \\ "The Sunken Keep") do
    Ash.create!(Atlas.Campaigns.Campaign, %{name: name}, actor: gm)
  end

  @doc "A new account that joined the campaign with its invitation. Returns `{player, character}`."
  def join_player(campaign, gm) do
    player = user()
    invitation = Ash.create!(Atlas.Campaigns.Invitation, %{campaign_id: campaign.id}, actor: gm)

    character =
      Ash.create!(Atlas.Campaigns.Character, %{token: invitation.token},
        action: :join,
        actor: player
      )

    {player, character}
  end

  @doc "A world entry made by the GM. It starts hidden. Pass `shown: true` to show it."
  def entry(gm, campaign, kind, name, attrs \\ %{}) do
    {shown, attrs} = Map.pop(attrs, :shown, false)

    entry =
      Ash.create!(
        Atlas.Content.Entry,
        Map.merge(%{campaign_id: campaign.id, kind: kind, name: name}, attrs),
        actor: gm
      )

    if shown,
      do: Ash.update!(entry, %{hidden: false}, action: :set_hidden, actor: gm),
      else: entry
  end

  @doc """
  A custom field made by the GM. `type` is text, number, boolean, select or entry. Pass `choices`
  for a select and `target_kind` for an entry field, and `gm_only: true` for a GM-only field.
  """
  def entry_field(gm, campaign, kind, label, type \\ :text, attrs \\ %{}) do
    Ash.create!(
      Atlas.Content.EntryField,
      Map.merge(%{campaign_id: campaign.id, kind: kind, label: label, type: type}, attrs),
      actor: gm
    )
  end

  def paragraph(text, id \\ "b1") do
    %{
      "id" => id,
      "type" => "paragraph",
      "props" => %{"textAlignment" => "left"},
      "content" => [%{"type" => "text", "text" => text, "styles" => %{}}],
      "children" => []
    }
  end

  @doc "The account registered with `email`."
  def user_by_email(email) do
    require Ash.Query

    Atlas.Accounts.User
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one!(authorize?: false)
  end

  @doc """
  Saves the JSON of one section through its `save_*` action, as `actor` (a user or an email).

  People change text only through live editing, so no API action does this. Tests use it to give
  a record its text and to check the action's rules. Options: `:revision` (default: the stored
  one) and `:schema_version` (default 1). Returns `{:ok, record}` or `{:error, error}`.
  """
  def save_section(resource, id, section, blocks, actor, opts \\ []) do
    actor = if is_binary(actor), do: user_by_email(actor), else: actor
    record = Ash.get!(resource, id, authorize?: false)

    params = %{
      json: blocks,
      schema_version: Keyword.get(opts, :schema_version, 1),
      expected_revision:
        Keyword.get(
          opts,
          :revision,
          Map.fetch!(record, Atlas.RichText.revision_attribute(section))
        )
    }

    record
    |> Ash.Changeset.for_update(Atlas.RichText.save_action(section), params, actor: actor)
    |> Ash.update()
  end

  def save_section!(resource, id, section, blocks, actor, opts \\ []) do
    {:ok, record} = save_section(resource, id, section, blocks, actor, opts)
    record
  end
end
