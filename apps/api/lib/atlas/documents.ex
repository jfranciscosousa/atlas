defmodule Atlas.Documents do
  @moduledoc "Server-held state of the documents that people edit together."
  use Ash.Domain, otp_app: :atlas, extensions: [AshAi]

  tools do
    tool :write_text, Atlas.Documents.Doc, :write_text,
      description: """
      Write Markdown into a rich-text section, as a live edit that open editors see at once.
      kind and section: campaign (description, progress_rewards), session (log, prep),
      character (description, secret_notes), note (body), player_log (body).
      id is the id of that record. mode replace (default) replaces the section, append adds to it.
      Read the section first with get_*: its Markdown is complete, so you can change it and write it
      back. Replace refuses to drop an image the section has now, unless remove_images is true.
      Pass the section's revision from get_* as expected_revision: the write fails if someone
      changed the section since. The result has the new revision: a second edit can use it.
      To change one passage, prefer edit_text.
      Markdown supports headings, lists, check lists, quotes, code, dividers, bold, italic,
      strike, links and images (![](atlas-image:ID) on its own line). To link a character, session
      or note, write [@Name](atlas-entry:KIND:ID) with KIND character, session or note; the editor
      shows the current name. get_* texts show existing links in this form. Tables are not supported.
      Not kept in the text: underline, colors, alignment and image width.
      """

    tool :edit_text, Atlas.Documents.Doc, :edit_text,
      description: """
      Change one passage of a rich-text section and leave every other block as it is, with its
      images and formatting. kind, section and id are as in write_text. find is text that occurs
      exactly once in the section, as get_* shows it (it may not span two blocks). replace is the
      new text; it may hold Markdown. Only the block that holds find is rewritten. If that block has
      underline, colors or alignment, which Markdown cannot keep, the edit is refused. Pass the
      revision from get_* as expected_revision. The result has the new revision: a second edit can
      use it.
      """
  end

  resources do
    resource Atlas.Documents.Doc
  end
end
