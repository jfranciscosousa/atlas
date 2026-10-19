defmodule Atlas.RichText do
  @moduledoc """
  Ash resource extension for parent-owned BlockNote documents.

  Each declared section generates `<section>_json`, `<section>_schema_version` and
  `<section>_revision` attributes plus a narrow `save_<section>` update action.

      rich_text do
        section :description
      end
  """

  @section %Spark.Dsl.Entity{
    name: :section,
    describe: "A rich-text section stored in flat columns on the parent resource.",
    target: Atlas.RichText.Section,
    args: [:name],
    schema: [name: [type: :atom, required: true, doc: "The section name."]]
  }

  @rich_text %Spark.Dsl.Section{
    name: :rich_text,
    describe: "Rich-text sections.",
    entities: [@section]
  }

  use Spark.Dsl.Extension,
    sections: [@rich_text],
    transformers: [Atlas.RichText.Transformer]

  @doc "Names of the rich-text sections a resource declares."
  def sections(resource) do
    resource |> Spark.Dsl.Extension.get_entities([:rich_text]) |> Enum.map(& &1.name)
  end

  def json_attribute(name), do: :"#{name}_json"
  def schema_version_attribute(name), do: :"#{name}_schema_version"
  def revision_attribute(name), do: :"#{name}_revision"
  def save_action(name), do: :"save_#{name}"
end
