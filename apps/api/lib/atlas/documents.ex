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
      Markdown supports headings, lists, check lists, quotes, code, dividers, bold, italic,
      strike, links and images (![](atlas-image:ID) on its own line). To link a character, session
      or note, write [@Name](atlas-entry:KIND:ID) with KIND character, session or note; the editor
      shows the current name. get_* texts show existing links in this form. Tables are not supported.
      """
  end

  resources do
    resource Atlas.Documents.Doc
  end
end
