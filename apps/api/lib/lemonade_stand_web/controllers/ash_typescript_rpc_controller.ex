defmodule LemonadeStandWeb.AshTypescriptRpcController do
  use LemonadeStandWeb, :controller

  plug :require_user

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:lemonade_stand, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:lemonade_stand, conn, params)
    json(conn, result)
  end

  defp require_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Sign in to continue."})
      |> halt()
    end
  end
end
