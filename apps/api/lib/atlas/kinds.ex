defmodule Atlas.Kinds do
  @moduledoc """
  The one list of content kinds. A kind is a name such as `"note"` that a rich-text section, a
  mention, a search hit and an MCP tool use to point at a record.

  Each kind has a resource and the rich-text sections of that resource. Several kinds may share
  one resource: the resource then has a `kind` attribute that tells them apart.
  Every module that needs a list of kinds reads it here: the live-editing documents, the mentions,
  the search projection and the MCP tool descriptions.

  This module holds data only and names resources as atoms, so any module may read it at compile
  time. A test checks that the sections below equal the sections that each resource declares.
  """

  @base [
    %{
      kind: :campaign,
      resource: Atlas.Campaigns.Campaign,
      sections: [:description, :progress_rewards],
      mention?: false
    },
    %{
      kind: :session,
      resource: Atlas.Campaigns.Session,
      sections: [:log, :prep],
      mention?: true
    },
    %{
      kind: :character,
      resource: Atlas.Campaigns.Character,
      sections: [:description, :secret_notes],
      mention?: true
    },
    %{
      kind: :note,
      resource: Atlas.Content.Note,
      sections: [:body],
      mention?: true
    },
    %{
      kind: :player_log,
      resource: Atlas.Campaigns.PlayerLog,
      sections: [:body],
      mention?: false
    }
  ]

  # The world entries share one resource. `Atlas.Content.EntrySpec` names their kinds.
  @entries for kind <- Atlas.Content.EntrySpec.kinds(),
               do: %{
                 kind: kind,
                 resource: Atlas.Content.Entry,
                 sections: [:description, :secret_notes],
                 mention?: true
               }

  @kinds @base ++ @entries

  @by_name Map.new(@kinds, &{Atom.to_string(&1.kind), &1})
  @by_kind Map.new(@kinds, &{&1.kind, &1})

  @doc "Every kind, as an atom."
  @spec kinds() :: [atom()]
  def kinds, do: Enum.map(@kinds, & &1.kind)

  @doc "Every kind, as a string."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@kinds, &Atom.to_string(&1.kind))

  @doc "The kinds that a mention may point to, as strings."
  @spec mention_names() :: [String.t()]
  def mention_names, do: for(%{mention?: true, kind: kind} <- @kinds, do: Atom.to_string(kind))

  @doc "The kinds that a mention may point to, as atoms."
  @spec mention_kinds() :: [atom()]
  def mention_kinds, do: for(%{mention?: true, kind: kind} <- @kinds, do: kind)

  @doc "The kind with this name. A string from a client never becomes an atom."
  @spec fetch(String.t() | atom()) :: {:ok, atom()} | :error
  def fetch(name) when is_binary(name) do
    case Map.fetch(@by_name, name) do
      {:ok, %{kind: kind}} -> {:ok, kind}
      :error -> :error
    end
  end

  def fetch(kind) when is_atom(kind) and not is_nil(kind),
    do: if(Map.has_key?(@by_kind, kind), do: {:ok, kind}, else: :error)

  def fetch(_), do: :error

  @doc "The resource that stores the kind."
  @spec resource(atom() | String.t()) :: module()
  def resource(kind), do: entry!(kind).resource

  @doc "The rich-text sections of the kind."
  @spec sections(atom() | String.t()) :: [atom()]
  def sections(kind), do: entry!(kind).sections

  @doc "Every section name of any kind."
  @spec all_sections() :: [atom()]
  def all_sections, do: @kinds |> Enum.flat_map(& &1.sections) |> Enum.uniq()

  @doc "The distinct resources, each with its kinds."
  @spec resources() :: [{module(), [atom()]}]
  def resources do
    @kinds
    |> Enum.group_by(& &1.resource, & &1.kind)
    |> Enum.sort_by(fn {_resource, [first | _]} -> Enum.find_index(kinds(), &(&1 == first)) end)
  end

  @doc "The kinds that one resource stores."
  @spec kinds_of(module()) :: [atom()]
  def kinds_of(resource), do: for(%{resource: ^resource, kind: kind} <- @kinds, do: kind)

  @doc """
  The kind of a stored row. A resource with one kind needs no `kind` column. A resource with
  several kinds has one, and the row must carry it.
  """
  @spec record_kind(module(), map()) :: atom()
  def record_kind(resource, row) do
    case kinds_of(resource) do
      [kind] -> kind
      _many -> row |> Map.fetch!(:kind) |> to_kind!()
    end
  end

  @doc "True when the resource stores several kinds and has a `kind` attribute."
  @spec shared_resource?(module()) :: boolean()
  def shared_resource?(resource), do: match?([_, _ | _], kinds_of(resource))

  defp to_kind!(kind) when is_atom(kind), do: kind
  defp to_kind!(name) when is_binary(name), do: elem(fetch(name), 1)

  defp entry!(kind) do
    case fetch(kind) do
      {:ok, kind} -> Map.fetch!(@by_kind, kind)
      :error -> raise ArgumentError, "unknown kind #{inspect(kind)}"
    end
  end
end
