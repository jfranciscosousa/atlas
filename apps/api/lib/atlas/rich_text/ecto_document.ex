defmodule Atlas.RichText.EctoDocument do
  @moduledoc false
  # Postgrex encodes any JSON term into jsonb; Ecto's own :map type would reject a root array.
  use Ecto.Type

  def type, do: :map
  def cast(value) when is_list(value), do: {:ok, value}
  def cast(_), do: :error
  def load(value) when is_list(value), do: {:ok, value}
  def load(_), do: :error
  def dump(value) when is_list(value), do: {:ok, value}
  def dump(_), do: :error
end
