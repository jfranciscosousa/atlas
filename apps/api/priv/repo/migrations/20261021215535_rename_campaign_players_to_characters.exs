defmodule Atlas.Repo.Migrations.RenameCampaignPlayersToCharacters do
  @moduledoc """
  A campaign player becomes a character. The rows stay: each one is the first character of its
  account. An account may now have several characters in a campaign, and a character has a name.
  """

  use Ecto.Migration

  def up do
    rename table(:campaign_players), to: table(:characters)

    execute "ALTER INDEX campaign_players_pkey RENAME TO characters_pkey"

    execute "ALTER TABLE characters RENAME CONSTRAINT campaign_players_campaign_id_fkey TO characters_campaign_id_fkey"

    execute "ALTER TABLE characters RENAME CONSTRAINT campaign_players_user_id_fkey TO characters_user_id_fkey"

    drop_if_exists unique_index(:characters, [:campaign_id, :user_id],
                     name: "campaign_players_unique_player_index"
                   )

    alter table(:characters) do
      add :name, :text
    end
  end

  def down do
    alter table(:characters) do
      remove :name
    end

    # Rows added since the rename may hold a second character of one account. They cannot stay.
    execute """
    DELETE FROM characters c USING characters first
    WHERE c.campaign_id = first.campaign_id AND c.user_id = first.user_id
      AND (c.inserted_at, c.id) > (first.inserted_at, first.id)
    """

    create unique_index(:characters, [:campaign_id, :user_id],
             name: "campaign_players_unique_player_index"
           )

    execute "ALTER TABLE characters RENAME CONSTRAINT characters_user_id_fkey TO campaign_players_user_id_fkey"

    execute "ALTER TABLE characters RENAME CONSTRAINT characters_campaign_id_fkey TO campaign_players_campaign_id_fkey"

    execute "ALTER INDEX characters_pkey RENAME TO campaign_players_pkey"

    rename table(:characters), to: table(:campaign_players)
  end
end
