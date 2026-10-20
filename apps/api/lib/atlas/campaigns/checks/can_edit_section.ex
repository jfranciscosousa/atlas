defmodule Atlas.Campaigns.Checks.CanEditSection do
  @moduledoc """
  Passes when the actor can run the parent's `save_<section>` action on the campaign, note, or
  session the changeset names. Uploading into a section needs the same access as editing it.
  """
  use Ash.Policy.SimpleCheck

  alias Atlas.Images.Parent

  @impl true
  def describe(_), do: "actor can edit this section of the parent"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    kind = Ash.Changeset.get_attribute(changeset, :parent_type)
    parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)
    section = Ash.Changeset.get_attribute(changeset, :section)

    with true <- not is_nil(kind) and not is_nil(parent_id) and not is_nil(section),
         {:ok, parent} <- Ash.get(Parent.module(kind), parent_id, actor: actor) do
      Ash.can?({parent, :"save_#{section}"}, actor)
    else
      _ -> false
    end
  end

  def match?(_, _, _), do: false
end
