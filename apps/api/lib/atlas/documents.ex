defmodule Atlas.Documents do
  @moduledoc "Server-held state of the documents that people edit together."
  use Ash.Domain, otp_app: :atlas

  resources do
    resource Atlas.Documents.Doc
  end
end
