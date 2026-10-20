defmodule Atlas.Images.Parent do
  @moduledoc """
  The resources whose rich-text sections can hold images: a campaign, a note, or a session.
  An image belongs to one section of one parent and follows that section's access rules.
  """
  alias Atlas.Campaigns.{Campaign, Session}
  alias Atlas.Content.Note

  @kinds %{campaign: Campaign, note: Note, session: Session}
  # The upload route names the parent in the URL. Strings map to atoms here, so a client
  # can never mint atoms.
  @paths %{"campaigns" => :campaign, "notes" => :note, "sessions" => :session}

  def kinds, do: Map.keys(@kinds)

  def module(kind), do: Map.fetch!(@kinds, kind)

  def kind(module), do: Enum.find_value(@kinds, fn {kind, mod} -> mod == module && kind end)

  def from_path(path), do: Map.fetch(@paths, path)

  @doc "True when the actor may read this section. Field policies hide a section the actor lacks."
  def section_readable?(kind, parent_id, section, actor) do
    case Ash.get(module(kind), parent_id, actor: actor) do
      {:ok, parent} ->
        not match?(
          %Ash.ForbiddenField{},
          Map.fetch!(parent, Atlas.RichText.json_attribute(section))
        )

      _ ->
        false
    end
  end
end
