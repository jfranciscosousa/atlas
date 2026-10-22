defmodule Atlas.Campaigns.Session.DraftLog do
  @moduledoc """
  Asks a language model for a new final log of a session. It reads the log and every player log
  and returns Markdown. It never reads the prep, which only the GM sees, and it saves nothing:
  the GM reads the draft and accepts it in the editor.
  """
  use Ash.Resource.Actions.Implementation

  require Logger

  alias Atlas.Campaigns.PlayerLog
  alias Atlas.Campaigns.Session
  alias Atlas.RichText.PlainText

  @system """
  You write the final log of one session of a tabletop RPG campaign. Players read it as the
  record of what happened at the table. The GM's log and the players' logs are your only source.
  Return two things: `draft` and `conflicts`.

  `conflicts` lists every direct contradiction between two sources about the same fact, for
  example one player says the ghost spoke and another says it was silent, or a player and the GM
  name different people. Write one short sentence per conflict. Say who says what, by name, and
  call the GM "the GM". Leave the list empty when there is none. A source that leaves out a
  detail is never a conflict, even when another source states that detail: for example, one
  player says Mira found a tripwire and nobody else mentions it. That is not a conflict. A
  different level of detail, or a different word for the same act (smashed, punched), is never a
  conflict. Do not guess.
  Only the GM reads `conflicts`. Never write a conflict, the logs, the players or the GM in the
  draft: the draft tells the story of the characters.

  In the draft, follow the GM's log when it contradicts a player. When players contradict each
  other and the GM's log is silent on it, leave the contested detail out. Never add events,
  names, motives or details that the sources do not contain. Write only what the characters
  saw, heard or learned.

  Style: a vivid, readable story in the past tense, in the third person. Use full paragraphs,
  not notes. Name the characters. Keep memorable lines of dialogue in quotation marks. Put the
  key moment of a scene or its outcome in **bold**. Write in English, unless the logs are mostly in another language: then use that language.

  Structure, in this order, as Markdown:
  1. `## 📍 Location`: one short paragraph that names the places of the session.
  2. One `##` heading per story beat, in time order. Give each heading a short title in plain text, without bold,
     for example `## The Way Was Open—But Not for Them Alone`. Use two to six beats. Add one
     `### Title` only when a beat has real sub-scenes.
  3. `## ➡️ What's Next`, only when the session ended in the middle of a scene or a fight. Say in
     one or two sentences where the party stands.
  4. `## Progress & Rewards`, only when the source states XP, treasure or a level-up. List only
     those facts, as bullet points. Never invent amounts.

  Use only headings, paragraphs, **bold**, *italic* and bullet lists. Do not use a code block, a
  table, an image or a horizontal rule. Do not add a title, a preface or a note about your work.
  """

  # The action may override any of these options.
  @defaults [
    model: "openrouter:deepseek/deepseek-v4.1-flash",
    req_llm: Application.compile_env(:atlas, :req_llm, ReqLLM),
    # Low reasoning keeps the wait short. The fastest provider shortens it more.
    req_llm_opts: [
      reasoning_effort: :low,
      provider_options: [openrouter_provider: %{sort: "throughput"}]
    ]
  ]

  @impl true
  def run(input, opts, context) do
    opts = Keyword.merge(@defaults, opts)
    actor = context.actor
    session = Ash.get!(Session, input.arguments.id, actor: actor)

    player_logs =
      PlayerLog
      |> Ash.Query.for_read(:list, %{session_id: session.id}, actor: actor)
      |> Ash.Query.load(:author_name)
      |> Ash.read!()

    sources =
      [{"Log of the GM", session.log_json}] ++
        Enum.map(player_logs, &{"Log of the player #{&1.author_name}", &1.body_json})

    parts =
      for {title, json} <- sources, text = PlainText.render(json), text != "" do
        "## #{title}\n\n#{text}"
      end

    case parts do
      [] ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :id,
           message: "has no log text to use yet"
         )}

      parts ->
        user = "Session #{session.number}#{if session.title, do: ": #{session.title}"}\n\n"
        prompt = {@system, user <> Enum.join(parts, "\n\n")}

        ask(input, opts, context, prompt)
    end
  end

  # ReqLLM raises when the API key is missing or the network is down. A raise would reach the
  # client as a bare 500.
  defp ask(input, opts, context, prompt) do
    AshAi.Actions.Prompt.run(input, Keyword.put(opts, :prompt, fn _, _ -> prompt end), context)
  rescue
    error ->
      Logger.error("Draft log failed: " <> Exception.message(error))

      {:error,
       Ash.Error.Changes.InvalidArgument.exception(
         field: :id,
         message:
           "cannot be drafted now: the AI is not available. Check the server's OpenRouter key"
       )}
  end
end
