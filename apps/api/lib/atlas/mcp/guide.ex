defmodule Atlas.Mcp.Guide do
  @moduledoc """
  The text of the MCP tool descriptions that teach a client the block format. The lists of block
  types, props and styles come from the validation code, so the text cannot drift from it.
  """

  alias Atlas.Content.{EntrySpec, RelationSpec}
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

  @doc "A line per kind of world entry: its statuses and fields."
  def entry_kinds do
    Enum.map_join(EntrySpec.kinds(), "\n", fn kind ->
      spec = EntrySpec.fetch!(kind)

      fields =
        spec.fields
        |> Enum.map(& &1.key)
        |> then(&if(&1 == [], do: "none", else: Enum.join(&1, ", ")))

      "  - #{kind}: status #{Enum.join(spec.statuses, ", ")} (default #{hd(spec.statuses)}); fields: #{fields}"
    end)
  end

  @doc "The description of `list_entries`."
  def list_entries do
    """
    List the world entries of a campaign that you can read: NPCs, locations, factions, items,
    creatures and plots. Set kind to list one kind, and archived to true for the archived ones.
    A player never gets a hidden entry. Use get_entry for the details. To keep the entries whose
    custom field has one value, give custom_field_id (from list_entry_fields) and
    custom_field_value as text: a number as "3", a boolean as "true", a select as one of its
    choices, an entry field as the id of the entry. Text ignores case.
    """
  end

  @doc "The description of `get_entry`."
  def get_entry do
    """
    Read a world entry: its kind, name, status, hidden flag, fields, parent location, image id and
    relations, with its description and GM-only secret notes as blocks (see edit_blocks) and their
    revisions. A relation has the id to remove it, the text from this entry ("member of" or
    "members") and the other end. Fields: all text, readable by everyone who reads the entry.
    custom_values lists the custom fields of the kind that you may read, in order: id, label, type,
    gm_only, choices (a select), target_kind (an entry field) and value. A field with no value has
    value null. The value of an entry field is {kind, id, label, restricted, shown}: if you cannot
    read that entry, the label is "Restricted entry" and the id is null.
    """
  end

  @doc "The description of `create_entry`."
  def create_entry do
    """
    Create a world entry in a campaign that you run as GM. kind is #{Enum.join(EntrySpec.kinds(), ", ")}.
    It starts hidden: only you read it until you show it with set_entry_hidden. Statuses and
    fields by kind:
    #{entry_kinds()}
    Give status and fields only when you know them. A field is text; a faction's reputation is
    plain text. Use edit_blocks for the description and the secret notes. A location may have a
    parent location (parent_id) of the same campaign. image_id is an image from upload_image.
    custom_values sets custom fields: a map of field id (from list_entry_fields) to value.
    """
  end

  @doc "The description of `update_entry`."
  def update_entry do
    """
    Change the status, the fields, the parent location or the image of a world entry. Only the GM
    may. fields is merged into the stored fields: send only the fields that change, and use a
    blank value to clear one. Set parent_id (a location only) or image_id to null to clear it.
    custom_values is a map of custom field id (from list_entry_fields) to value. It changes only the
    fields it names; null or "" clears one. A number is a number, a boolean is true or false, a
    select is one of its choices, and an entry field is the id of a non-archived entry of its
    target kind in this campaign.
    Statuses and fields by kind:
    #{entry_kinds()}
    """
  end

  @doc "The description of `list_entry_fields`."
  def list_entry_fields do
    """
    List the custom fields of a campaign, in order. A custom field is a field that the GM defines for
    one kind of world entry in this campaign only, for example "Kingdom" (a link to a location) on
    locations. Set kind to list one kind, and archived to true for the archived fields. The values
    are in get_entry (custom_values) and are set with update_entry. A player never gets a GM-only
    field or its values.
    """
  end

  @doc "The description of `create_entry_field`."
  def create_entry_field do
    """
    Define a custom field for one kind of entry (#{Enum.join(EntrySpec.kinds(), ", ")}) in a campaign
    that you run as GM. label has 1 to 60 characters and must not equal another active field of the
    kind, ignoring case, or a built-in field. type is #{Enum.join(Atlas.Content.EntryField.types(), ", ")}. A select needs choices (a
    list of names). An entry field needs target_kind: the kind of entry it points to. gm_only true
    hides the field and its values from players. The type and the target kind never change. The
    field goes last in its kind.
    """
  end

  @doc "The description of `update_entry_field`."
  def update_entry_field do
    """
    Change a custom field: label, gm_only and, for a select, choices. choices is the whole new list.
    To rename a choice, put the new name in choices and give renamed_choices as {"old": "new"}: the
    stored values follow. A choice that is gone from the list and that entries use is refused with
    the number of entries; rename it, or change those entries first. The type and the target kind
    never change. Only the GM may.
    """
  end

  @doc "The description of `add_entry_relation`."
  def add_entry_relation do
    relations =
      Enum.map_join(RelationSpec.describe(), "\n", fn spec ->
        "  - #{spec.relation} (\"#{spec.label}\"): from #{Enum.join(spec.from, ", ")} to #{Enum.join(spec.to, ", ")}"
      end)

    """
    Relate two ends in a campaign that you run as GM. An end is an entry or a character: give
    its kind (character, #{Enum.join(EntrySpec.kinds(), ", ")}) and its id. The relation reads
    from the first end to the second. label is optional text, for example "staff". Relations and
    the kinds they join:
    #{relations}
    Players see a relation only when they can read both ends.
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
