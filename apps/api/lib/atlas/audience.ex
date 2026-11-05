defmodule Atlas.Audience do
  @moduledoc """
  Who reads a rich-text section. An MCP client reads the audience next to the text, so an agent
  can see which text is secret before it copies the text into a section that more people read.

  The audiences reuse the levels of a note's visibility, and add `:gm_only`:

    * `:gm_only` - only the GM.
    * `:only_me` - only the owner. A private note, and a skill.
    * `:me_and_gm` - the owner and the GM.
    * `:character` - also the player of the linked character.
    * `:everyone` - every member of the campaign, players included.

  `of/3` has one clause for each section of each kind, and no fallback. A new section raises until
  someone decides its audience here. A hidden world entry has the audience `:gm_only` in its
  description, because only the GM reads it until the GM shows it. Archiving changes no audience.

  The web app shows the same labels (`labels/0`). `apps/web/src/lib/audience.ts` repeats them, and
  `Atlas.AudienceTest` fails when the two differ.
  """

  alias Atlas.Content.EntrySpec
  alias Atlas.Kinds

  @entry_kinds EntrySpec.kinds()

  @labels %{
    gm_only: "GM only",
    only_me: "Private",
    me_and_gm: "Owner and GM",
    character: "Character",
    everyone: "Everyone"
  }

  @type t :: :gm_only | :only_me | :me_and_gm | :character | :everyone

  @doc "Every audience, from the narrowest to the widest."
  @spec all() :: [t()]
  def all, do: [:gm_only, :only_me, :me_and_gm, :character, :everyone]

  @doc "The label of each audience, as the app shows it."
  @spec labels() :: %{t() => String.t()}
  def labels, do: @labels

  @doc "True when a player may read text with this audience."
  @spec players_read?(t()) :: boolean()
  def players_read?(audience), do: audience in [:character, :everyone]

  @doc """
  The audience of one section. `state` holds what the audience depends on: `:visibility` of a note,
  `:hidden` of a world entry. Other kinds ignore it.
  """
  @spec of(atom(), atom(), map()) :: t()
  def of(kind, section, state \\ %{})

  def of(:campaign, section, _state) when section in [:description, :progress_rewards],
    do: :everyone

  def of(:session, :log, _state), do: :everyone
  def of(:session, :prep, _state), do: :gm_only
  def of(:character, :description, _state), do: :everyone
  def of(:character, :secret_notes, _state), do: :gm_only
  def of(:player_log, :body, _state), do: :everyone
  def of(:skill, :body, _state), do: :only_me
  def of(:note, :body, %{visibility: visibility}), do: visibility
  def of(kind, :secret_notes, _state) when kind in @entry_kinds, do: :gm_only

  def of(kind, :description, %{hidden: hidden}) when kind in @entry_kinds,
    do: if(hidden, do: :gm_only, else: :everyone)

  @doc "The audience of a section of a record that was read."
  @spec of_record(struct(), atom()) :: t()
  def of_record(%resource{} = record, section) do
    of(
      Kinds.record_kind(resource, record),
      section,
      Map.take(record, [:hidden, :visibility])
    )
  end
end
