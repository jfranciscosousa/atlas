# Glossary

Domain terms for Atlas. Use these words in code and tests.

## People

- **Campaign**: one closed game with one GM and many players. Only members can access it.
- **GM**: the one person who runs a campaign. Use "GM", not "DM". Roles belong to a campaign, not to an account.
- **Player**: the person at the table: an account that plays one or more characters in a campaign. The GM is not a player. A person without an account has no player; the GM manages their character.
- **Character**: someone a player plays in a campaign. It has a name, which starts empty and shows as "Unnamed character", and a description. Its player is the account that created it, joined with it, or claimed it. A character with no player is unclaimed. A player may have several characters in one campaign. Every member reads a character. Its player and the GM write its description. Its player and the GM write its name.
- **Player name**: the name of the player of a character. It is the account's display name. For an unclaimed character it is the label the GM gave.
- **Unclaimed character**: a character the GM prepared for a person who has no account yet, or who never signs up. It has a player label, no account, and a claim link. Every member reads it. The GM writes its name and description. It makes nobody a member and has no player logs; player logs are optional.
- **Claim link**: the single-use link to one unclaimed character. Only the GM reads it. Whoever opens it sees the campaign and the character, signs up or signs in, and claims the character. The claimer becomes its player and a member, and the link stops working. The GM cannot claim.
- **Character description**: the rich text of a character. Every member reads it. Its player and the GM write it.
- **Secret notes**: the GM-only rich text of a character or a world entry. Only the GM reads and writes it.
- **Account**: a signed-in user. An account is not a character.
- **Member**: the GM or a player of a campaign. A player is a member as long as they have a character in it.
- **Invitation**: a reusable invite link to a campaign. It has no expiry and works until the GM revokes it. A campaign has at most one active invitation. Revoking stops future joins and keeps existing players.
- **MCP connection**: an MCP client (Claude, ChatGPT, opencode, pi) that an account allowed through OAuth. It acts as the account: it reads what the account can read, and it writes what the account can write. It deletes nothing, except that the GM removes a relation between two entries. Its text edits are live edits, like those of an editor. It reads and edits text as blocks, by block ID, in the JSON that the editor stores (see **Block**). The account lists and revokes its connections in Settings.

## Content

- **Entry**: a named record of a campaign that a mention or a search hit points to. Kinds: character, session, note, and the six kinds of world entry.
- **World entry**: a named thing of the game world. Kinds: NPC, location, faction, item, creature, plot. Only the GM creates, edits, archives, and restores it. It has a name, a status, built-in fields, custom fields, an optional image, a description, and GM-only secret notes. It is archived, never deleted. It is hidden when new. One resource holds every kind, and one spec in code lists the statuses and fields of each kind.
- **Hidden**: a world entry is hidden until the GM shows it to the players. Only the GM reads a hidden entry. The GM shows it and may hide it again. A player never sees a hidden entry: not in lists, search, mention labels (the label is "Restricted entry"), relations, or Preview as player.
- **Status**: one value of a fixed list per kind of world entry. NPC: alive, dead, missing, unknown (starts alive). Location: active, destroyed, abandoned (starts active). Faction: active, disbanded (starts active). Item: unknown, held, lost, destroyed (starts unknown). Creature: active, defeated (starts active). Plot: planned, active, done (starts planned).
- **Field**: a built-in text field of a world entry, rules-agnostic. It is the same in every campaign; a custom field is not. NPC: ancestry, gender. Location: type. Faction: type, reputation. Item: type. Creature: type, source. Plot: none. Everyone who reads the entry reads its fields. The GM writes them. XP and level are not fields: the campaign progress/rewards text covers them. No built-in field is a game-system number.
- **Custom field**: a field that the GM defines for one kind of world entry in one campaign only; another campaign does not have it. Example: "Dragonmark" (text) on factions, "Kingdom" (a link to a location) on locations, "True allegiance" (a link to a faction, GM only) on NPCs. A custom field has a label (1–60 characters, unique among the active fields of its kind in the campaign, ignoring case, and never the label of a built-in field of that kind), a type, an order, and a GM-only flag. Types: text, number, yes/no, select (the GM lists the choices), and entry (a link to a non-archived entry of one kind in the same campaign). The type and the target kind never change after creation; the label, the choices, the order and the GM-only flag do. Only the GM defines, changes, orders, archives and restores custom fields, and sets their values on entries. A value belongs to the field by its ID, so a rename changes no data, and an empty value is no value. A GM-only field is invisible to players: they never receive its definition or its values, from the app, MCP, search or Preview as player. A link to an entry that the reader cannot read shows "Restricted entry" with no ID, as a mention does. Renaming a select choice rewrites the stored values. Removing a choice that an entry uses is refused with the number of entries; the GM renames the choice or changes those entries first. A custom field is archived, never deleted: an archived field and its values are hidden everywhere, and a restore shows them again, last in the order. Custom field values do not take part in search. A list of one kind may be filtered by one custom field value (equality), by the same rules for every reader: a player cannot filter by a GM-only field.
- **Parent location**: a location may sit inside one other location of the same campaign. It has no cycles. A player sees the parent only when the parent is shown too.
- **Relation**: a link between two ends, each an entry or a character. The relations are fixed: member of, located in, headquarters of, held by, allied with, enemy of, involves. Each allows only some kinds at each end; involves goes from a plot to anything. A relation may have a short free label, for example "staff". Only the GM adds and removes relations. A reader sees a relation only when the reader can read both ends. An entry page shows its relations in both directions.
- **NPC**: a unique individual. Not the same as a creature.
- **Creature**: a reusable monster description. The bestiary is a set of creatures.
- **Faction**: an organization. It has a reputation toward the whole party, as plain text. Players and the GM read it. The GM writes it.
- **Note**: free-form text. Guides and handouts are notes. A plot is not a note: it is a world entry. A note has a visibility and may link to a character.
- **Session**: one play session of a campaign, numbered from 1. Only the GM manages it.
- **Session status**: *In prep* or *Done*. A session starts in prep. The GM marks it done after play and may move it back. Every member sees the status.
- **Log**: the final record of a session. Members read it. Only the GM edits it.
- **Conflict**: two logs of one session that directly contradict each other about the same fact. A log that leaves out a detail is not a conflict. The AI draft of a log reports conflicts to the GM only, never in the draft text.
- **Prep**: the GM-only text of a session. The GM plans in it and takes live notes in it during play.
- **Player log**: one player's recollection of a session. One per player per session. Every member reads every player log. Its author and the GM write it. The GM is not a player and writes none of their own.
- **Progress/rewards**: one campaign text that records what already happened. Members read it. Only the GM edits it.

## Text

- **Section**: one rich-text field of a resource, for example a campaign description. A section has its own access rule and its own revision number.
- **Live editing**: everyone who may edit a section edits it together and sees changes at once. The same editor does this for every section. The server keeps the shared document and checks the user's rights again on every message. Anyone who may read a section but not edit it sees the changes live and cannot type.
- **Presence**: who has a section open. Everyone who may read the section sees it, readers included. The server sets each person's name and colour. A client can send only its cursor.
- **Saved**: the server committed the change to the database. The editor shows "Saved" only after the server confirms it.
- **Revision**: the counter of a section's JSON. The server raises it each time live editing stores a change. No API action saves a section's JSON.
- **Epoch**: the number of times the shared document was rebuilt from the section's JSON, because something other than live editing changed the JSON. An editor that holds an older epoch must start over.
- **History**: the saved versions of a section. A restore creates a new revision.
- **Checkpoint**: a user-visible history version, made after 30 s without edits or every 5 min of editing.
- **Mention**: an inline @ link to another entry. It stores the kind and the ID, and shows the current name. Kinds: character, session, note, NPC, location, faction, item, creature, plot. A player is not a kind: mention the character. Every rich-text section accepts mentions. The author may mention any entry the author can read, hidden ones included. A reader who cannot read the entry sees "Restricted entry". MCP tools read a mention as a node with the kind, the ID and a read-only `label`, the current name looked up with the access of the reader; a write ignores the label. Search and the AI log draft read it as the plain name. The label of an archived note or world entry is "Deleted entry" for a reader who may read it; only the GM reads an archived world entry.
- **Block**: one unit of a section, as the editor stores it: an `id`, a `type`, `props`, `content` and nested `children`. Atlas allows only the types in `Atlas.RichText.Document`. MCP clients read and edit text by block ID, with `edit_blocks`; an update can carry the block's `hash` to refuse the edit when the block changed since the client read it. An MCP edit that removes an image needs `remove_images`, and one that deletes more than 10 blocks needs `delete_many`; an update that drops bold, links or mentions, or that has no `hash`, still applies and returns a warning. The text of an MCP edit is never Markdown.
- **Search**: shared fuzzy search for names and text the account may read, used by the app API, MCP, and AI. Campaign is an optional filter; without it, search covers all campaigns the account may read. Matching ignores case, accents, and punctuation, and accepts one edit for query words of 4–7 characters or two for longer words. A query word is a run of letters and digits that punctuation joins without a space; the query M.A.77 asks for ma77, which matches the text M.A.77 and MA77, never the letters m and a alone. Every query word must match, in any order, in the entry name together with one section. Titles rank before text: an exact title match first, a title match with a typo second, then exact words in the text, then near words. Within a rank, a title that is the query comes first, then one that starts with it, then the one with more matches in the text. The app and MCP show hits in this order, not grouped by kind. Hits include campaign names and IDs, with block IDs and plain-text snippets. Hidden entries and sections never affect matches, ranking, snippets, or counts. Custom field values are not searched. Archived notes and archived world entries are excluded.
- **Image**: an uploaded picture, converted to WebP. It stands alone, with no parent. A document stores its ID, never a URL. A world entry stores the ID of its image in the same way.

## Access

- **Shared**: readable by all members. Editable by all members once the note has visibility Everyone.
- **GM-only**: readable and editable only by the GM.
- **Visibility**: who reads a note. The owner or the GM sets it. Levels: Private, Owner and GM, Character, Everyone. A new note starts at Owner and GM.
- **Private**: only the owner reads the note. The GM does not read a player's private note.
- **Owner and GM**: the owner and the GM read the note.
- **Character note**: a note with visibility Character. The owner, the GM, and the player of the linked character read it. That player also edits the body. A player links only their own character. Until a player claims the character, only the owner and the GM read it. After the claim, the player reads it. Only the owner and the GM rename, share, or archive it.
- **Everyone**: all members read the note and edit its body.
- **Owner**: the member who created an entry. The owner manages it. The GM also manages it, except a player's private note.
- **Archived**: removed from active lists, never deleted. The owner or the GM can restore it. Other members never see an archived note or an archived world entry.
- **Restricted entry**: the label a reader sees for a link to an entry they cannot access, in a mention or in the value of a custom field.
- **Deleted entry**: the label an authorized reader sees for a link to an archived entry.
- **Preview as player**: a read-only page that shows a campaign the way a player sees it.
