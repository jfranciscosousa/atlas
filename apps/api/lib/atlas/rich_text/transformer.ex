defmodule Atlas.RichText.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias Atlas.RichText
  alias Atlas.RichText.{Document, Save}
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def after?(Ash.Resource.Transformers.ValidatePrimaryActions), do: true
  def after?(_), do: false

  @impl true
  def before?(Ash.Resource.Transformers.DefaultAccept), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    {:ok, dsl_state} = Builder.add_change(dsl_state, Atlas.Search.Sync)

    dsl_state
    |> Transformer.get_entities([:rich_text])
    |> Enum.reduce_while({:ok, dsl_state}, fn section, {:ok, dsl_state} ->
      case add_section(dsl_state, section) do
        {:ok, dsl_state} -> {:cont, {:ok, dsl_state}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp add_section(dsl_state, %{name: name} = section) do
    json = RichText.json_attribute(name)
    version = RichText.schema_version_attribute(name)
    revision = RichText.revision_attribute(name)
    action = RichText.save_action(name)

    with :ok <- check_free(dsl_state, [:attributes], [json, version, revision], section),
         :ok <- check_free(dsl_state, [:actions], [action], section) do
      dsl_state
      |> add_json_default(json)
      |> Builder.add_attribute(json, Document,
        allow_nil?: false,
        default: [],
        public?: true,
        writable?: false
      )
      |> Builder.add_attribute(version, :integer,
        allow_nil?: false,
        default: Document.schema_version(),
        public?: true,
        writable?: false
      )
      |> Builder.add_attribute(revision, :integer,
        allow_nil?: false,
        default: 0,
        public?: true,
        writable?: false
      )
      |> Builder.add_action(:update, action,
        accept: [],
        require_atomic?: false,
        arguments: [
          Builder.build_action_argument(:json, Document, allow_nil?: false),
          Builder.build_action_argument(:schema_version, :integer, allow_nil?: false),
          Builder.build_action_argument(:expected_revision, :integer, allow_nil?: false)
        ],
        changes: [Builder.build_action_change({Save, section: name})]
      )
    end
  end

  # A bare `[]` is not a valid jsonb column default.
  defp add_json_default(dsl_state, json) do
    defaults = Transformer.get_option(dsl_state, [:postgres], :migration_defaults) || []

    Transformer.set_option(
      dsl_state,
      [:postgres],
      :migration_defaults,
      Keyword.put(defaults, json, ~s|fragment("'[]'::jsonb")|)
    )
  end

  defp check_free(dsl_state, path, names, section) do
    taken = dsl_state |> Transformer.get_entities(path) |> MapSet.new(& &1.name)

    case Enum.filter(names, &MapSet.member?(taken, &1)) do
      [] ->
        :ok

      clashes ->
        {:error,
         DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           path: [:rich_text, :section, section.name],
           message: "rich-text section generates #{inspect(clashes)}, which already exists"
         )}
    end
  end
end
