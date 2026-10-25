defmodule Atlas.Mcp.Guide do
  @moduledoc """
  The text of the MCP tool descriptions that teach a client the block format. The lists of block
  types, props and styles come from the validation code, so the text cannot drift from it.
  """

  alias Atlas.Content.EntrySpec
  alias Atlas.Kinds
  alias Atlas.RichText.Collab.Blocks
  alias Atlas.RichText.Document

  @docs "https://www.blocknotejs.org/docs/foundations/document-structure"

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
    as in edit_blocks. The result has the section revision.

    #{blocks()}\
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
    creatures and plots. Set kind to list one kind, and archived to true for the archived ones.
    A player never gets a hidden entry. Each row has the id, the kind, the name and the hidden
    flag. Use get_entry for the text.
    """
  end

  @doc "The description of `get_entry`."
  def get_entry do
    """
    Read a world entry: its kind, name, hidden flag and archive state, with its description and
    its GM-only secret notes as blocks (see edit_blocks) and their revisions. An entry is text:
    read the description to learn what the entry is. Its state, details and relationships are in
    that text, not in fields. A player never receives the secret notes. A hidden or archived entry
    is readable by the GM alone.
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
    with edit_blocks. The description is what players read; the secret notes are yours alone.
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
