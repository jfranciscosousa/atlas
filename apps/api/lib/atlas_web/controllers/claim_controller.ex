defmodule AtlasWeb.ClaimController do
  use AtlasWeb, :controller

  alias Atlas.Campaigns.Character

  # The claim page shows who is invited before the person has an account, so this needs no session.
  # The token is the credential. A used or unknown token returns the same 404.
  def show(conn, %{"token" => token}) do
    Character
    |> Ash.Query.for_read(:by_claim_token, %{token: token})
    |> Ash.Query.load([:campaign_name, :gm_name])
    |> Ash.read_one(actor: conn.assigns[:current_user])
    |> case do
      {:ok, %Character{} = character} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{
          characterName: character.name,
          playerLabel: character.player_label,
          campaignName: character.campaign_name,
          gmName: character.gm_name
        })

      _ ->
        conn |> put_status(:not_found) |> json(%{error: "This claim link is no longer valid."})
    end
  end
end
