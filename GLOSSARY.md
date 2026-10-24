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
- **Secret notes**: the GM-only rich text of a character. Only the GM reads and writes it.
- **Account**: a signed-in user. An account is not a character.
- **Member**: the GM or a player of a campaign. A player is a member as long as they have a character in it.
- **Invitation**: a reusable invite link to a campaign. It has no expiry and works until the GM revokes it. A campaign has at most one active invitation. Revoking stops future joins and keeps existing players.
- **MCP connection**: an MCP client (Claude, ChatGPT, opencode, pi) that an account allowed through OAuth. It acts as the account: it reads what the account can read, and it writes what the account can write. It deletes nothing. Its text edits are live edits, like those of an editor. It reads and edits text as blocks, by block ID, in the JSON that the editor stores (see **Block**). The account lists and revokes its connections in Settings.

## Content

- **Entry**: a named item in a campaign. Kinds: character, NPC, creature, location, faction, item, note.
- **NPC**: a unique individual. Not the same as a creature.
- **Creature**: a reusable monster description. The bestiary is a set of creatures.
- **Faction**: an organization. It has a GM-only reputation toward the whole party.
- **Note**: free-form text. Guides, handouts, and plots are notes. A note has a visibility and may link to a character.
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
- **Mention**: an inline @ link to another entry. It stores the kind and the ID, and shows the current name. Kinds: character, session, note. A player is not a kind: mention the character. Every rich-text section accepts mentions. The author may mention any entry the author can read, hidden ones included. A reader who cannot read the entry sees "Restricted entry". MCP tools read a mention as a node with the kind, the ID and a read-only `label`, the current name looked up with the access of the reader; a write ignores the label. Search and the AI log draft read it as the plain name. The label of an archived note is "Deleted entry" for a reader who may read it.
- **Block**: one unit of a section, as the editor stores it: an `id`, a `type`, `props`, `content` and nested `children`. Atlas allows only the types in `Atlas.RichText.Document`. MCP clients read and edit text by block ID, with `edit_blocks`; an update can carry the block's `hash` to refuse the edit when the block changed since the client read it. An MCP edit that removes an image needs `remove_images`, and one that deletes more than 10 blocks needs `delete_many`; an update that drops bold, links or mentions, or that has no `hash`, still applies and returns a warning. The text of an MCP edit is never Markdown.
- **Search**: shared fuzzy search for names and text the account may read, used by the app API, MCP, and AI. Campaign is an optional filter; without it, search covers all campaigns the account may read. Matching ignores case, accents, and punctuation, and accepts one edit for query words of 4–7 characters or two for longer words. Every query word must match, in any order, in the entry name together with one section. Exact matches rank first. Hits include campaign names and IDs, with block IDs and plain-text snippets. Hidden entries and sections never affect matches, ranking, snippets, or counts. Archived notes are excluded.
- **Image**: an uploaded picture, converted to WebP. It stands alone, with no parent. The document stores its ID, never a URL.

## Access

- **Shared**: readable by all members. Editable by all members once the note has visibility Everyone.
- **GM-only**: readable and editable only by the GM.
- **Visibility**: who reads a note. The owner or the GM sets it. Levels: Private, Owner and GM, Character, Everyone. A new note starts at Owner and GM.
- **Private**: only the owner reads the note. The GM does not read a player's private note.
- **Owner and GM**: the owner and the GM read the note.
- **Character note**: a note with visibility Character. The owner, the GM, and the player of the linked character read it. That player also edits the body. A player links only their own character. Until a player claims the character, only the owner and the GM read it. After the claim, the player reads it. Only the owner and the GM rename, share, or archive it.
- **Everyone**: all members read the note and edit its body.
- **Owner**: the member who created an entry. The owner manages it. The GM also manages it, except a player's private note.
- **Archived**: removed from active lists, never deleted. The owner or the GM can restore it. Other members never see an archived note.
- **Restricted entry**: the label a reader sees for a link to an entry they cannot access.
- **Deleted entry**: the label an authorized reader sees for a link to an archived entry.
- **Preview as player**: a read-only page that shows a campaign the way a player sees it.
