defmodule Atlas.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email
  """

  use AshAuthentication.Sender

  import Swoosh.Email

  alias Atlas.Mailer

  @impl true
  def send(user, token, _) do
    new()
    |> from(Application.fetch_env!(:atlas, :mail_from))
    |> to(to_string(user.email))
    |> subject("Reset your password")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    url =
      Application.fetch_env!(:atlas, :frontend_url) <>
        "/password-reset/" <> URI.encode_www_form(params[:token])

    """
    <p>Click this link to reset your password:</p>
    <p><a href="#{url}">#{url}</a></p>
    """
  end
end
