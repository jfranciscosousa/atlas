defmodule Atlas.Campaigns.Image do
  @moduledoc """
  A converted image uploaded into one section of one campaign.

  Access always follows the section that owns the image. Documents store only the image ID,
  and signed URLs are issued per request after the section check.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Campaigns,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  require Ash.Query

  alias Atlas.Campaigns.Checks.CanEditSection

  @sections [:description, :progress_rewards]

  postgres do
    table "campaign_images"
    repo Atlas.Repo

    custom_indexes do
      index [:campaign_id, :section]
    end
  end

  typescript do
    type_name "CampaignImage"
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:campaign_id, :section, :storage_key, :byte_size, :width, :height, :animated]
      change relate_actor(:uploader)
    end

    action :signed_url, :string do
      argument :id, :uuid, allow_nil?: false
      argument :campaign_id, :uuid, allow_nil?: false
      argument :section, :atom, allow_nil?: false, constraints: [one_of: @sections]

      run Atlas.Campaigns.Image.SignedUrl
    end
  end

  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    # Both sections are readable by every member, so an image follows the same rule.
    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       campaign,
                       gm_id == ^actor(:id) or exists(players, user_id == ^actor(:id))
                     )
                   )
    end

    policy action_type(:create) do
      authorize_if CanEditSection
    end

    policy action(:signed_url) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :section, :atom do
      allow_nil? false
      constraints one_of: @sections
    end

    attribute :storage_key, :string, allow_nil?: false
    attribute :content_type, :string, allow_nil?: false, default: "image/webp"
    attribute :byte_size, :integer, allow_nil?: false
    attribute :width, :integer, allow_nil?: false
    attribute :height, :integer, allow_nil?: false
    attribute :animated, :boolean, allow_nil?: false, default: false

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Atlas.Campaigns.Campaign do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :uploader, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end

  @doc "True when every ID names an image uploaded into this section of this campaign."
  def all_in_section?(campaign_id, section, ids) do
    # Internal integrity check on server-derived values. It reveals nothing to the caller.
    count =
      __MODULE__
      |> Ash.Query.filter(campaign_id == ^campaign_id and section == ^section and id in ^ids)
      |> Ash.count!(authorize?: false)

    count == length(ids)
  end
end
