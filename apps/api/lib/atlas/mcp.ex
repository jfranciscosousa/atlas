defmodule Atlas.Mcp do
  @moduledoc """
  The OAuth server behind the MCP endpoint. An account connects an MCP client (Claude, ChatGPT,
  opencode, pi) once, and each connection is a grant that the account can list and revoke.
  """
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Atlas.Mcp.Client do
      rpc_action :get_mcp_client, :read, get_by: [:id]
    end

    resource Atlas.Mcp.Grant do
      rpc_action :list_mcp_connections, :list
      rpc_action :revoke_mcp_connection, :destroy
    end
  end

  resources do
    resource Atlas.Mcp.Client
    resource Atlas.Mcp.Grant
  end
end
