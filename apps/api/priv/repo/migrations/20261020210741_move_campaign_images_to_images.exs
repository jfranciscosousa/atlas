defmodule Atlas.Repo.Migrations.MoveCampaignImagesToImages do
  @moduledoc """
  Images are not campaign-owned: the table loses its campaign column and becomes `images`.
  Written by hand so the rows and the constraint names survive the rename.
  """

  use Ecto.Migration

  def up do
    alter table(:campaign_images) do
      remove :campaign_id
    end

    rename table(:campaign_images), to: table(:images)

    execute "ALTER TABLE images RENAME CONSTRAINT campaign_images_pkey TO images_pkey"

    execute "ALTER TABLE images RENAME CONSTRAINT campaign_images_uploader_id_fkey TO images_uploader_id_fkey"

    execute "ALTER INDEX campaign_images_parent_type_parent_id_section_index RENAME TO images_parent_type_parent_id_section_index"
  end

  def down do
    execute "ALTER INDEX images_parent_type_parent_id_section_index RENAME TO campaign_images_parent_type_parent_id_section_index"

    execute "ALTER TABLE images RENAME CONSTRAINT images_uploader_id_fkey TO campaign_images_uploader_id_fkey"

    execute "ALTER TABLE images RENAME CONSTRAINT images_pkey TO campaign_images_pkey"

    rename table(:images), to: table(:campaign_images)

    alter table(:campaign_images) do
      add :campaign_id,
          references(:campaigns,
            column: :id,
            name: "campaign_images_campaign_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    execute """
    UPDATE campaign_images SET campaign_id = CASE parent_type
      WHEN 'campaign' THEN parent_id
      WHEN 'note' THEN (SELECT campaign_id FROM notes WHERE notes.id = parent_id)
      WHEN 'session' THEN (SELECT campaign_id FROM sessions WHERE sessions.id = parent_id)
    END
    """

    alter table(:campaign_images) do
      modify :campaign_id, :uuid, null: false
    end

    create index(:campaign_images, [:campaign_id, :section])
  end
end
