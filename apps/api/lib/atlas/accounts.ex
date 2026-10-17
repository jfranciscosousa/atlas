defmodule Atlas.Accounts do
  use Ash.Domain, otp_app: :atlas, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Atlas.Accounts.User do
      rpc_action :get_profile, :get_profile
      rpc_action :update_profile, :update_profile
    end
  end

  resources do
    resource Atlas.Accounts.Token
    resource Atlas.Accounts.User
  end
end
