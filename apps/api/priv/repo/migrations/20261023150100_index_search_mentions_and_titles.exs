defmodule Atlas.Repo.Migrations.IndexSearchMentionsAndTitles do
  use Ecto.Migration

  def up do
    create table(:search_titles, primary_key: false) do
      add :kind, :text, primary_key: true
      add :record_id, :uuid, primary_key: true
      add :title, :text, null: false
      add :words, {:array, :text}, null: false
    end

    create index(:search_titles, [:words], using: :gin)

    alter table(:search_sections) do
      add :mention_keys, {:array, :text}, null: false, default: []
      add :joined_mentions, :boolean, null: false, default: false
    end

    create index(:search_sections, [:mention_keys], using: :gin)
  end

  def down do
    drop table(:search_titles)

    alter table(:search_sections) do
      remove :mention_keys
      remove :joined_mentions
    end
  end
end
