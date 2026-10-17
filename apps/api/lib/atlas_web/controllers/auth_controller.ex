defmodule AtlasWeb.AuthController do
  use AtlasWeb, :controller
  use AshAuthentication.Phoenix.Controller

  defdelegate sign_out(conn, params), to: AtlasWeb.SessionController, as: :delete

  def success(conn, {:password, :reset_request}, _user, _token) do
    AtlasWeb.SessionController.respond(conn, conn.assigns[:current_user])
  end

  def success(conn, {:password, :reset}, _user, _token) do
    AtlasWeb.SessionController.delete(conn, %{})
  end

  def success(conn, _activity, user, _token) do
    conn
    |> store_in_session(user)
    |> AtlasWeb.SessionController.respond(user)
  end

  def failure(conn, activity, reason) do
    {status, message, fields} =
      case activity do
        {:password, phase} when phase in [:register, :reset] ->
          fields = validation_fields(reason)

          message =
            cond do
              map_size(fields) > 0 ->
                "Check the highlighted fields."

              phase == :reset ->
                "This password reset link is invalid or has expired. Request a new link."

              true ->
                "We could not create your account. Please try again."
            end

          {422, message, fields}

        {:confirm_new_user, :confirm} ->
          {422, "This confirmation link is invalid or has expired.", %{}}

        {:password, :reset_request} ->
          {422, "Could not send reset instructions. Please try again.", %{}}

        _ ->
          {401, "Incorrect email or password", %{}}
      end

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: message, fields: fields})
  end

  defp validation_fields(%AshAuthentication.Errors.AuthenticationFailed{caused_by: reason}),
    do: validation_fields(reason)

  defp validation_fields(%Ash.Error.Invalid{errors: errors}) do
    Enum.reduce(errors, %{}, fn
      %{field: field} = error, fields
      when field in [:display_name, :email, :password, :password_confirmation] ->
        Map.put(fields, field, validation_message(field, error))

      %Ash.Error.Changes.InvalidChanges{fields: [:email], message: "has already been taken"},
      fields ->
        Map.put(
          fields,
          :email,
          validation_message(:email, %{message: "has already been taken"})
        )

      _, fields ->
        fields
    end)
  end

  defp validation_fields(_reason), do: %{}

  defp validation_message(:email, %{message: "has already been taken"}),
    do: "An account with this email already exists. Sign in or reset your password."

  defp validation_message(field, %Ash.Error.Changes.Required{}) do
    case field do
      :display_name -> "Display name is required."
      :email -> "Email address is required."
      :password -> "Password is required."
      :password_confirmation -> "Confirm your password."
    end
  end

  defp validation_message(:display_name, _error), do: "Use a name between 1 and 100 characters."
  defp validation_message(:email, _error), do: "Enter a valid email address."
  defp validation_message(:password, _error), do: "Use at least 8 characters."
  defp validation_message(:password_confirmation, _error), do: "Passwords must match."
end
