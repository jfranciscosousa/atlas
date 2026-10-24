defmodule Mix.Tasks.Atlas.DevUser do
  @shortdoc "Creates a confirmed account for local sign-in"
  @moduledoc """
  Creates a confirmed account, or confirms an existing one, so that you can sign in without the
  confirmation email. It does not run in production.

      mix atlas.dev_user [EMAIL] [--password PASSWORD] [--name NAME]

  The defaults are `agent@example.com` and `dev-password-123`. An existing account keeps its password.
  """
  use Mix.Task

  import Ecto.Query

  @impl Mix.Task
  def run(args) do
    if Mix.env() == :prod, do: Mix.raise("atlas.dev_user does not run in production")
    Mix.Task.run("app.start")

    {opts, rest} = OptionParser.parse!(args, strict: [password: :string, name: :string])
    email = List.first(rest, "agent@example.com")
    password = Keyword.get(opts, :password, "dev-password-123")

    existing? = Atlas.Repo.exists?(from(u in "users", where: u.email == ^email))
    unless existing?, do: register(email, Keyword.get(opts, :name, "Agent"), password)

    Atlas.Repo.update_all(
      from(u in "users", where: u.email == ^email and is_nil(u.confirmed_at)),
      set: [confirmed_at: DateTime.utc_now()]
    )

    if existing? do
      Mix.shell().info("#{email} is confirmed. It keeps its password.")
    else
      Mix.shell().info("#{email} / #{password}")
    end
  end

  defp register(email, name, password) do
    Ash.create!(
      Atlas.Accounts.User,
      %{
        email: email,
        display_name: name,
        password: password,
        password_confirmation: password
      },
      action: :register_with_password,
      authorize?: false
    )
  end
end
