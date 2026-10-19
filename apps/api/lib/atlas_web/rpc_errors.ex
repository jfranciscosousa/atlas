defimpl AshTypescript.Rpc.Error, for: Ash.Error.Changes.StaleRecord do
  # Lets the editor tell a revision conflict from a generic failure.
  def to_error(_error) do
    %{
      message: "This section was changed elsewhere. Reload to see the latest version.",
      short_message: "Stale revision",
      type: "stale_revision",
      vars: %{},
      fields: [],
      path: []
    }
  end
end
