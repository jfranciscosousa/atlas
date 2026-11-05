defmodule Atlas.Search.Request do
  @moduledoc false
  use Ash.Resource,
    otp_app: :atlas,
    domain: Atlas.Content,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "SearchRequest"
  end

  actions do
    action :search, :map do
      argument :campaign_id, :uuid
      argument :query, :string, allow_nil?: false, constraints: [max_length: 200]

      argument :kinds, {:array, :atom}, constraints: [items: [one_of: Atlas.Kinds.kinds()]]

      # Omit it to find archived and active notes and world entries alike. True finds only the
      # archived ones, false only the active ones.
      argument :archived, :boolean

      argument :limit, :integer, allow_nil?: false, default: 20, constraints: [min: 1, max: 50]

      # Skips the first hits of the ranked list, to read the next page.
      argument :offset, :integer,
        allow_nil?: false,
        default: 0,
        constraints: [min: 0, max: 10_000]

      run Atlas.Search
    end
  end

  policies do
    policy action(:search) do
      authorize_if actor_present()
    end
  end
end
