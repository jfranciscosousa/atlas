defmodule Atlas.Content.Skill do
  @moduledoc """
  A skill or procedure that the GM wants an AI agent to follow, for example how to write a
  session recap or how to build an NPC. The text is for the GM's agents, read through MCP.

  A skill belongs to an account and is global: it is not tied to a campaign. Only its owner reads
  or writes it, so no player ever sees it. Only an account that is the GM of a campaign creates
  one. A skill has a name, a description and a body. The description says when to use the skill;
  an agent reads the descriptions first and opens a body only when one fits the task.

  A skill is archived, never deleted.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource, Atlas.RichText]

  alias Atlas.Content.Checks.ActorRunsACampaign

  postgres do
    table "skills"
    repo Atlas.Repo

    custom_indexes do
      index [:owner_id, :name, :id]
    end
  end

  typescript do
    type_name "Skill"
  end

  rich_text do
    section(:body, mentions: false)
  end

  actions do
    defaults [:read]

    read :list do
      argument :archived, :boolean, default: false, allow_nil?: false

      filter expr(not is_nil(archived_at) == ^arg(:archived))

      prepare build(sort: [name: :asc, id: :asc])
    end

    create :create do
      primary? true
      accept [:name, :description]
      change relate_actor(:owner)
    end

    update :update do
      primary? true
      accept [:name, :description]
    end

    update :archive do
      require_atomic? false
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :restore do
      change set_attribute(:archived_at, nil)
    end

    # The body comes back as Markdown: an agent follows a skill and never edits it from this read.
    # Used by the MCP tools.
    action :describe, :map do
      argument :id, :uuid, allow_nil?: false

      run {Atlas.Mcp.Describe,
           fields: [:id, :name, :description, :archived_at], sections: [:body], markdown: [:body]}
    end
  end

  # The owner alone reads and writes a skill. Everyone else gets not found.
  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if ActorRunsACampaign
    end

    policy action(:describe) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(owner_id == ^actor(:id))
    end

    policy action([:update, :archive, :restore, :save_body]) do
      authorize_if expr(owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200, trim?: true
    end

    # When to use the skill. An agent decides from this text whether to open the body.
    attribute :description, :string do
      allow_nil? false
      default ""
      public? true
      constraints max_length: 1000, trim?: true, allow_empty?: true
    end

    attribute :archived_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end
end
