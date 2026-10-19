defmodule Atlas.Fixtures do
  @moduledoc false

  def user(email \\ "gm#{System.unique_integer([:positive])}@example.com") do
    Ash.create!(
      Atlas.Accounts.User,
      %{
        email: email,
        display_name: "Test User",
        password: "a-secure-password",
        password_confirmation: "a-secure-password"
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  def campaign(gm, name \\ "The Sunken Keep") do
    Ash.create!(Atlas.Campaigns.Campaign, %{name: name}, actor: gm)
  end

  def paragraph(text, id \\ "b1") do
    %{
      "id" => id,
      "type" => "paragraph",
      "props" => %{"textAlignment" => "left"},
      "content" => [%{"type" => "text", "text" => text, "styles" => %{}}],
      "children" => []
    }
  end
end
