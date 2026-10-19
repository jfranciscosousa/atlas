defmodule Atlas.Campaigns do
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Atlas.Campaigns.Campaign do
      rpc_action :list_campaigns, :list
      rpc_action :get_campaign, :read, get_by: [:id]
      rpc_action :create_campaign, :create
      rpc_action :save_campaign_description, :save_description
      rpc_action :save_campaign_progress_rewards, :save_progress_rewards
    end

    resource Atlas.Campaigns.Image do
      rpc_action :get_campaign_image_url, :signed_url
    end
  end

  resources do
    resource Atlas.Campaigns.Campaign
    resource Atlas.Campaigns.Image
  end
end
