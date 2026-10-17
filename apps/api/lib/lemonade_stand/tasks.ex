defmodule LemonadeStand.Tasks do
  use Ash.Domain,
    otp_app: :lemonade_stand,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource LemonadeStand.Tasks.Todo do
      rpc_action :list_todos, :list
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy
    end
  end

  resources do
    resource LemonadeStand.Tasks.Todo
  end
end
