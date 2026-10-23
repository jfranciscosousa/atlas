defmodule Atlas.Images.Image do
  @moduledoc """
  A converted image. The file lives in object storage (Cloudflare R2 in production, local disk in
  development); this row holds its metadata. An image belongs to no campaign, note, or session.

  Documents store only the image ID. The ID is a random UUID that nobody can guess, and whoever
  has it, signed in, can ask for a signed URL that lasts a few minutes (the model Discord uses).
  """
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Images,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  require Ash.Query

  alias Atlas.Images.Checks.ActorIsCampaignMember

  postgres do
    table "images"
    repo Atlas.Repo
  end

  typescript do
    type_name "Image"
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:storage_key, :byte_size, :width, :height, :animated]
      change relate_actor(:uploader)
    end

    # Stores an image from a public URL. Used by the MCP tools.
    action :upload_from_url, :map do
      argument :url, :string, allow_nil?: false
      run Atlas.Images.Image.UploadFromUrl
    end

    # Stores an image sent as base64 text. Used by the MCP tools.
    action :upload_from_base64, :map do
      argument :data, :string, allow_nil?: false
      run Atlas.Images.Image.UploadFromBase64
    end

    action :signed_url, :string do
      argument :id, :uuid, allow_nil?: false
      run Atlas.Images.Image.SignedUrl
    end
  end

  policies do
    policy always() do
      forbid_unless actor_present()
      authorize_if always()
    end

    # No RPC action reads a row. The signed-URL action is the only way to get a file.
    policy action_type(:read) do
      authorize_if always()
    end

    # Storage costs money, so only people who play in some campaign may upload.
    policy action_type(:create) do
      authorize_if ActorIsCampaignMember
    end

    # `Uploads` checks the create rule before it does any work.
    policy action([:upload_from_url, :upload_from_base64]) do
      authorize_if always()
    end

    policy action(:signed_url) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

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

  @doc "True when every ID names a stored image."
  def all_exist?(ids) do
    ids = Enum.uniq(ids)
    # Internal integrity check on document content. It reveals nothing to the caller.
    images =
      __MODULE__
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.sort(:id)
      |> Ash.Query.lock("FOR SHARE")
      |> Ash.read!(authorize?: false)

    length(images) == length(ids)
  end
end
