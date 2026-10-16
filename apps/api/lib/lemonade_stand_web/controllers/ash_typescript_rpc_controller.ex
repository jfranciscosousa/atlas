defmodule LemonadeStandWeb.AshTypescriptRpcController do
  use LemonadeStandWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:lemonade_stand, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:lemonade_stand, conn, params)
    json(conn, result)
  end
end
