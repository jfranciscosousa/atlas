defmodule Atlas.Accounts do
  use Ash.Domain, otp_app: :atlas

  resources do
    resource Atlas.Accounts.Token
    resource Atlas.Accounts.User
  end
end
