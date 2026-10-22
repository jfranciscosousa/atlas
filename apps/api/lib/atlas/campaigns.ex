defmodule Atlas.Campaigns do
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Atlas.Campaigns.Campaign do
      rpc_action :list_campaigns, :list
      rpc_action :get_campaign, :read, get_by: [:id]
      rpc_action :create_campaign, :create
    end

    resource Atlas.Campaigns.Session do
      rpc_action :list_sessions, :list
      rpc_action :get_session, :read, get_by: [:id]
      rpc_action :create_session, :create
      rpc_action :update_session_details, :update_details
      rpc_action :draft_session_log, :draft_log
    end

    resource Atlas.Campaigns.PlayerLog do
      rpc_action :list_player_logs, :list
      rpc_action :create_player_log, :create
    end

    resource Atlas.Campaigns.Character do
      rpc_action :list_characters, :list
      rpc_action :get_character, :read, get_by: [:id]
      rpc_action :create_character, :create
      rpc_action :rename_character, :rename
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
    resource Atlas.Campaigns.Character
    resource Atlas.Campaigns.Invitation
  end
end
