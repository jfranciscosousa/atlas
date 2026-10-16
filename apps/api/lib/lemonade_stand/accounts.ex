defmodule LemonadeStand.Accounts do
  use Ash.Domain, otp_app: :lemonade_stand

  resources do
    resource LemonadeStand.Accounts.Token
    resource LemonadeStand.Accounts.User
  end
end
