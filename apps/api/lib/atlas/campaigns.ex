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

    resource Atlas.Campaigns.Session do
      rpc_action :list_sessions, :list
      rpc_action :get_session, :read, get_by: [:id]
      rpc_action :create_session, :create
      rpc_action :update_session_details, :update_details
      rpc_action :save_session_log, :save_log
      rpc_action :save_session_prep, :save_prep
    end

    resource Atlas.Campaigns.PlayerLog do
      rpc_action :list_player_logs, :list
      rpc_action :create_player_log, :create
      rpc_action :save_player_log_body, :save_body
    end

    resource Atlas.Campaigns.CampaignPlayer do
      rpc_action :list_campaign_players, :list
      rpc_action :join_campaign, :join
    end

    resource Atlas.Campaigns.Invitation do
      rpc_action :get_active_invitation, :active, not_found_error?: false
      rpc_action :get_invitation_by_token, :by_token, not_found_error?: false
      rpc_action :create_invitation, :create
      rpc_action :revoke_invitation, :revoke
    end
  end

  resources do
    resource Atlas.Campaigns.Campaign
    resource Atlas.Campaigns.Session
    resource Atlas.Campaigns.PlayerLog
    resource Atlas.Campaigns.CampaignPlayer
    resource Atlas.Campaigns.Invitation
  end
end
