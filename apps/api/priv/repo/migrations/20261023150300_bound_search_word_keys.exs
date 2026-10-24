defmodule Atlas.Repo.Migrations.BoundSearchWordKeys do
  use Ecto.Migration

  def up do
    alter table(:search_words) do
      add :ordinal, :integer
    end

    flush()

    execute """
    UPDATE search_words w SET ordinal = ranked.ordinal
    FROM (
      SELECT ctid, (row_number() OVER (PARTITION BY kind, record_id, section ORDER BY word) - 1)::integer AS ordinal
      FROM search_words
    ) ranked WHERE w.ctid = ranked.ctid
    """

    execute "ALTER TABLE search_words DROP CONSTRAINT search_words_pkey"
    execute "ALTER TABLE search_words ALTER COLUMN ordinal SET NOT NULL"
    execute "ALTER TABLE search_words ADD PRIMARY KEY (kind, record_id, section, ordinal)"

    alter table(:search_sections) do
      add :has_long_words, :boolean, null: false, default: false
    end

    flush()
    Atlas.Search.Projection.backfill!()
  end

  def down do
    raise "Unbounded search tokens cannot safely use a word-based primary key"
  end
end
