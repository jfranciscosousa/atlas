defmodule Mix.Tasks.Atlas.DevUserTest do
  use Atlas.DataCase, async: false

  import ExUnit.CaptureIO

  alias Atlas.Accounts.User

  defp sign_in(email, password) do
    User
    |> Ash.Query.for_read(:sign_in_with_password, %{email: email, password: password})
    |> Ash.read_one(authorize?: false)
  end

  test "creates an account that can sign in without the confirmation email" do
    capture_io(fn ->
      Mix.Tasks.Atlas.DevUser.run(["new@example.com", "--password", "secret-pass-1"])
    end)

    assert {:ok, %User{}} = sign_in("new@example.com", "secret-pass-1")
  end

  test "confirms an account that was registered through the app and keeps its password" do
    Atlas.Fixtures.user("pending@example.com")
    assert {:error, _} = sign_in("pending@example.com", "a-secure-password")

    capture_io(fn -> Mix.Tasks.Atlas.DevUser.run(["pending@example.com"]) end)

    assert {:ok, %User{}} = sign_in("pending@example.com", "a-secure-password")
  end
end
