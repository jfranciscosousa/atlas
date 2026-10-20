defmodule Atlas.Images.Image do
  @moduledoc """
  A converted image. The file lives in object storage; this row holds its metadata and the
  section it was uploaded into: a section of a campaign, a note, or a session.

  Access always follows the section that owns the image. Documents store only the image ID,
  and signed URLs are issued per request after the section check.
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Images,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  require Ash.Query

  alias Atlas.Images.Checks.CanEditSection

  @sections [:description, :progress_rewards, :body, :log, :prep]
  @kinds Atlas.Images.Parent.kinds()

  postgres do
    table "images"
    repo Atlas.Repo

    custom_indexes do
      index [:parent_type, :parent_id, :section]
    end
  end

  typescript do
    type_name "Image"
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :parent_type,
        :parent_id,
        :section,
        :storage_key,
        :byte_size,
        :width,
        :height,
        :animated
      ]

      change relate_actor(:uploader)
    end

    action :signed_url, :string do
      argument :id, :uuid, allow_nil?: false
      argument :parent_type, :atom, allow_nil?: false, constraints: [one_of: @kinds]
      argument :parent_id, :uuid, allow_nil?: false
      argument :section, :atom, allow_nil?: false, constraints: [one_of: @sections]

      run Atlas.Images.Image.SignedUrl
    end
  end

  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    # The row holds only metadata, and no RPC action reads it. The signed-URL action checks
    # that the actor can read the section that holds the image.
    policy action_type(:read) do
      authorize_if actor_present()
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

    attribute :parent_type, :atom do
      allow_nil? false
      constraints one_of: @kinds
    end

    attribute :parent_id, :uuid, allow_nil?: false

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
    belongs_to :uploader, Atlas.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end

  @doc "True when every ID names an image uploaded into this section of this parent."
  def all_in_section?(parent_type, parent_id, section, ids) do
    # Internal integrity check on server-derived values. It reveals nothing to the caller.
    count =
      __MODULE__
      |> Ash.Query.filter(
        parent_type == ^parent_type and parent_id == ^parent_id and section == ^section and
          id in ^ids
      )
      |> Ash.count!(authorize?: false)

    count == length(ids)
  end
end
