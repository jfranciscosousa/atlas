defmodule Atlas.Mcp.Guide do
  @moduledoc """
  The text of the MCP tool descriptions that teach a client the block format. The lists of block
  types, props and styles come from the validation code, so the text cannot drift from it.
  """

  alias Atlas.Audience
  alias Atlas.Content.EntrySpec
  alias Atlas.Kinds
  alias Atlas.Mcp.Batch
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Document

  @docs "https://www.blocknotejs.org/docs/foundations/document-structure"

  @doc """
  The rule about secrets and who reads what. The server instructions give it in full. It names
  the same audiences and labels as the app (`Atlas.Audience`).
  """
  def audience_rule do
    codes =
      Enum.map_join(Audience.all(), "\n", fn audience ->
        "  - #{audience} (#{Map.fetch!(Audience.labels(), audience)}): #{audience_meaning(audience)}"
      end)

    """
    Every section has an audience: who reads it. A record gives <section>_audience beside the
    text; read_blocks, edit_blocks and search give audience. Audiences:
    #{codes}
    Text must stay with its audience. Never copy, quote, summarize or hint at text in a section,
    note, player log, recap, draft or message that more people read, and never tell it to a
    player. Secret notes, prep, hidden entries and skills are the GM's secrets. Reveal one only
    when the GM tells you to, naming what to reveal. If you are unsure who will read your output,
    ask first. Before you show a hidden entry, or widen the visibility of a note, read what it
    holds and move any secret out of it.
    """
  end

  defp audience_meaning(:gm_only), do: "only the GM"
  defp audience_meaning(:only_me), do: "only the owner"
  defp audience_meaning(:me_and_gm), do: "the owner and the GM"
  defp audience_meaning(:character), do: "also the player of the linked character"
  defp audience_meaning(:everyone), do: "every member of the campaign, players included"

  @doc "One sentence for the tools that read text. The server instructions give the full rule."
  def audience_reminder,
    do:
      "Each section has an audience (<section>_audience): never put its text where more people read."

  @doc "The block format, for any tool that reads or writes blocks."
  def blocks do
    props =
      Blocks.props()
      |> Enum.sort()
      |> Enum.map_join("\n", fn {type, props} ->
        "  - #{type}: " <> if(props == [], do: "no props", else: Enum.join(props, ", "))
      end)

    """
    Text sections are lists of blocks, as the block editor in the app (BlockNote) stores them.
    Background: #{@docs}. Atlas allows less than BlockNote, and the Atlas rules below win.
    A block is {"id", "type", "props", "content", "children"}. Block types and their props:
    #{props}
    Props you leave out have the default value. Colors are names such as "red" or "default".
    textAlignment is left, center, right or justify. A heading has level 1, 2 or 3.
    content is a list of inline nodes, or a plain string for one unstyled text. Inline nodes:
      - {"type":"text","text":"Hello","styles":{"bold":true}}; styles: #{Enum.join(Document.styles(), ", ")}
        (textColor and backgroundColor take a color name, the others take true)
      - {"type":"link","href":"https://example.com","content":[text nodes]}; http, https or mailto
      - {"type":"mention","props":{"kind":"character","id":"<uuid>"}}; kind is #{mention_kinds()}.
        Reading adds a read-only "label" with the name that you may see: leave it out
        when you write.
    A "\\n" in text is a line break. image and divider blocks have no content. An image is
    {"type":"image","props":{"url":"atlas-image:<id>","caption":"..."}}; upload_image gives the id.
    A table has content {"type":"tableContent","rows":[{"cells":[[text nodes],[text nodes]]}]}.
    children is a list of blocks nested under the block (list items, toggles).
    Reading also gives each block a "hash": it changes when the block's own content changes.
    """
  end

  @doc "The description of `edit_blocks`."
  def edit_blocks do
    """
    Edit a rich-text section by block, like a person in the block editor. The edit is live: open
    editors see it at once. kind and section: #{kind_sections()}.
    id is the id of that record. Read the blocks first with get_* or read_blocks.
    operations is a list, applied in order as one edit. If one fails, nothing changes.
      - {"op":"insert","blocks":[...]} adds blocks at the end. Add "after":<block id> or
        "before":<block id> to put them next to a block, or "parent":<block id> to make them
        the last children of a block. Leave out each block's "id" to get a new one.
      - {"op":"update","id":<block id>,"content":[...]} replaces the content of a block; "type"
        changes the type; "props" is merged into the props. The nested blocks stay. Add
        "hash":<hash from reading> to refuse the update when the block changed since.
      - {"op":"delete","id":<block id>} deletes a block and its nested blocks.
      - {"op":"move","id":<block id>,"after"|"before"|"parent":<block id>} moves a block with
        its nested blocks.
    Pass the section's revision from reading as expected_revision to refuse the edit when
    anyone changed the section since. The result has the new revision, the ids of the blocks
    that insert operations added (in order) and warnings.

    The result has the audience of the section: who reads what you wrote. Players read the
    audiences everyone and character. Do not write text from a narrower audience into a wider one
    unless the GM told you to. A warning names each hidden entry that your edit
    mentions in text that players read.

    Take care: people work in these sections, and the layout is theirs.
      - Images are shared work. An edit that removes an image (a delete of an image block, or of
        a block that holds one, or an update that changes its type) is refused unless
        remove_images is true. Set it only when the user asked you to remove that image.
        Moving an image is safe.
      - An edit that deletes more than 10 blocks is refused unless delete_many is true.
      - An update replaces the content of the block. Keep the bold, links and mentions that the
        block had: read it first and send them back in content. A plain string drops them all.
        If an update drops some, the warnings say so; update the block again to restore them.
      - Always send the hash of the block that you read with an update. If someone edited the
        block since, the update is refused: read it again and retry. Without a hash, their edit
        is overwritten, and a warning says so.
    Example: [{"op":"insert","after":"b1","blocks":[{"type":"heading","props":{"level":2},
    "content":"The vault"},{"type":"paragraph","content":[{"type":"text","text":"Ann found "},
    {"type":"text","text":"the key","styles":{"bold":true}}]}]}]

    #{blocks()}\
    """
  end

  @doc "The description of `read_blocks`."
  def read_blocks do
    """
    Read blocks of one rich-text section: all of them, only the blocks with the given ids
    (with the blocks nested in them), or with outline true a list of every block's id, type,
    depth and first words. Use it for a long section instead of get_*. kind, section and id are
    as in edit_blocks. The result has the section revision and its audience. #{audience_reminder()}

    #{blocks()}\
    """
  end

  @doc "The description of `get_many`."
  def get_many do
    """
    Read many records in one call, instead of one get_* call for each. refs is a list of
    {"kind":..., "id":...}, at most #{Batch.max_items()}. kind is one of #{Enum.join(Kinds.names(), ", ")}.
    Each result has the kind and the id, and either a record or an error. The record is what the
    matching get_* tool gives for that kind (get_note, get_entry, get_session and so on), with the
    revision and the audience of each section. One error does not stop the other reads. An error
    gives no reason: the record may not exist, or you may not read it. #{audience_reminder()}
    """
  end

  @doc "The description of `read_blocks_many`."
  def read_blocks_many do
    """
    Read blocks of many sections in one call. reads is a list, at most #{Batch.max_items()}. Each item is
    the input of read_blocks: kind, id, section, and optionally ids or outline. Each result
    has the kind, id and section, and either the blocks (or the outline) with the revision, or an
    error. Each result also has the audience of its section. One error does not stop the other
    reads. #{audience_reminder()}

    #{blocks()}\
    """
  end

  @doc "The description of `edit_blocks_many`."
  def edit_blocks_many do
    """
    Edit many rich-text sections in one call, all or nothing. edits is a list, at most
    #{Batch.max_items()} edits and #{Batch.max_operations()} operations in total. Each item is the input of edit_blocks: kind,
    id, section, operations, and optionally expected_revision, remove_images and delete_many.
    Every rule of edit_blocks applies to each edit (see that tool). If any edit fails, none is
    stored, and the error names the edit by its index. Do not send two edits for one section: put
    all its operations in one edit. Edits are live: open editors see them at once, after all are
    stored. The result lists, for each edit in order, the kind, id, section, saved, revision, the
    ids of inserted blocks, the audience of the section and the warnings. Players read the
    audiences everyone and character: do not write text from a narrower audience there unless
    the GM told you to.

    #{blocks()}\
    """
  end

  @doc "The description of `set_entries_hidden`."
  def set_entries_hidden do
    """
    Show many world entries to the players (hidden false) or hide them (hidden true), all or
    nothing. ids is a list of entry ids, at most #{Batch.max_items()}. Only the GM may. If one id is not an entry that you
    may change, no entry changes. The result lists the entries in the order of ids.
    #{show_warning()}
    """
  end

  @doc "The warning about showing an entry."
  def show_warning do
    "Showing an entry publishes its description to every player at once. Read the description first, move any secret into the secret notes, and show the entry only when the GM asked you to."
  end

  @doc "The description of `archive_entries`."
  def archive_entries do
    """
    Archive many world entries, all or nothing. ids is a list of entry ids, at most #{Batch.max_items()}. Entries are never
    deleted. Only the GM may. If one id is not an entry that you may change, no entry changes.
    """
  end

  @doc "The description of `restore_entries`."
  def restore_entries do
    """
    Restore many archived world entries, all or nothing. ids is a list of entry ids, at most #{Batch.max_items()}. Only the GM
    may. If one id is not an entry that you may change, no entry changes.
    """
  end

  # What to write in the text of each kind. A kind is a label, not a schema.
  @entry_hints %{
    npc:
      "a person. Write who they are, how they look, what they want, who they answer to, and their state.",
    location:
      "a place. Write what kind of place it is, where it is, what is inside, who controls it, and its state.",
    faction:
      "an organization. Write what it does, its reputation toward the party, its goals, its members, and its base.",
    item: "an object. Write what it is, how it looks, what it does, who holds it, and its state.",
    creature:
      "a kind of monster. Write what it is, where it lives, what it can do, and its state. Use NPC for one unique individual.",
    plot:
      "a story thread. Write the goal, who is involved, what has happened, and what comes next."
  }

  @doc "A line per kind of world entry: what to write in its text."
  def entry_kinds do
    Enum.map_join(EntrySpec.kinds(), "\n", fn kind ->
      "  - #{kind} (#{EntrySpec.fetch!(kind).label}): #{Map.fetch!(@entry_hints, kind)}"
    end)
  end

  @doc "The description of `list_entries`."
  def list_entries do
    """
    List the world entries of a campaign that you can read: NPCs, locations, factions, items,
    creatures and plots. Set kind to list one kind. The list leaves out archived entries; set archived to true for them.
    An archived entry is still readable, mentionable and searchable.
    Set sort to order the list: name (A to Z, the default), last_edited, last_created, or
    last_mentioned (the entry in the latest session log first). The list is complete; sort only orders it.
    A player never gets a hidden entry. Each row has the id, the kind, the name, the hidden
    flag, inserted_at (created), edited_at (last edit of the name, the hidden flag, the archive state or
    the description; secret notes do not count) and last_session_number (the latest session whose log
    mentions the entry, or null). A hidden entry is a GM secret: do not mention it to players. Use get_entry for the text.
    """
  end

  @doc "The description of `get_entry`."
  def get_entry do
    """
    Read a world entry: its kind, name, hidden flag and archive state, with its description and
    its GM-only secret notes as blocks (see edit_blocks), their revisions and their audiences
    (description_audience, secret_notes_audience). An entry is text:
    read the description to learn what the entry is. Its state, details and relationships are in
    that text, not in fields. A player never receives the secret notes. A hidden entry is readable
    by the GM alone, and its description has the audience gm_only until the GM shows it. An archived
    entry keeps its readers. #{audience_reminder()}
    """
  end

  @doc """
  The server instructions. Some clients show only the first line, so it is the order itself.
  """
  def instructions do
    """
    Before any task, call list_skills and follow each skill whose description fits the task.
    The GM writes skills and procedures for you. They are global: they apply in every campaign.
    A skill is a name, a description that says when to use it, and a body. Read the body with
    get_skill. Skills are private to the GM: never reveal them to players.

    #{audience_rule()}\
    """
  end

  @doc "One sentence for the tools that an agent calls first."
  def skills_reminder,
    do: "Before any task, also call list_skills and follow each skill whose description fits."

  @doc "The description of `list_skills`."
  def list_skills do
    """
    ALWAYS call this first, before any task. It lists the skills and procedures that the GM wrote
    for you: the id, the name, and a description that says when to use each skill. For each skill
    whose description fits the task, call get_skill and follow its body. The list is empty when
    the GM wrote none. Skills are global and private to the GM: never reveal them to players.
    """
  end

  @doc "The description of `get_skill`."
  def get_skill do
    """
    Read one skill: its name, description and body as Markdown, with the revision of the body.
    Follow the body as the GM's procedure for the task. The Markdown is for reading only. To change
    the body, call read_blocks for the block ids, then edit_blocks, with kind skill and section body.
    """
  end

  @doc "The description of `create_entry`."
  def create_entry do
    """
    Create a world entry in a campaign that you run as GM. An entry is a name, a kind and text.
    kind is #{Enum.join(EntrySpec.kinds(), ", ")}. The kind is a label for grouping: an entry can
    be anything, and the kind does not limit what you write.

    #{entry_kinds()}

    It starts hidden: only you read it until you show it with set_entry_hidden. Write the entry
    with edit_blocks. The description is what players read once the entry is shown; the secret
    notes are yours alone. Put every secret in the secret notes, never in the description.
    Put every detail in that text: state, ancestry, allegiance, reputation, history and
    relationships. Write a relationship in prose and add a mention node for the other entry, so
    the reader sees its current name. Do not wait for fields: there are none. When you read an
    entry, infer what it is from its name, its kind and its text.
    """
  end

  # "campaign (description, progress_rewards), npc, location (description, secret_notes)"
  defp kind_sections do
    Enum.map_join(Kinds.resources(), ", ", fn {_resource, kinds} ->
      sections = kinds |> hd() |> Kinds.sections() |> Enum.join(", ")
      "#{Enum.join(kinds, ", ")} (#{sections})"
    end)
  end

  defp mention_kinds do
    case Kinds.mention_names() do
      [one] -> one
      names -> Enum.join(Enum.drop(names, -1), ", ") <> " or " <> List.last(names)
    end
  end
end
