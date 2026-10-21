# Glossary

Domain terms for Atlas. Use these words in code and tests.

## People

- **Campaign**: one closed game with one GM and many players. Only members can access it.
- **GM**: the one person who runs a campaign. Use "GM", not "DM". Roles belong to a campaign, not to an account.
- **Player**: the person at the table: an account that plays one or more characters in a campaign. The GM is not a player.
- **Character**: someone a player plays in a campaign. It has a name, which starts empty and shows as "Unnamed character", and a description. Its player is the account that created or joined with it. A player may have several characters in one campaign. Every member reads a character. Its player and the GM write its description. Only its player writes its name.
- **Player name**: the name of the player of a character. It is the account's display name.
- **Character description**: the rich text of a character. Every member reads it. Its player and the GM write it.
- **Secret notes**: the GM-only rich text of a character. Only the GM reads and writes it.
- **Account**: a signed-in user. An account is not a character.
- **Member**: the GM or a player of a campaign. A player is a member as long as they have a character in it.
- **Invitation**: a reusable invite link to a campaign. It has no expiry and works until the GM revokes it. A campaign has at most one active invitation. Revoking stops future joins and keeps existing players.

## Content

- **Entry**: a named item in a campaign. Kinds: character, NPC, creature, location, faction, item, note.
- **NPC**: a unique individual. Not the same as a creature.
- **Creature**: a reusable monster description. The bestiary is a set of creatures.
- **Faction**: an organization. It has a GM-only reputation toward the whole party.
- **Note**: free-form text. Guides, handouts, and plots are notes.
- **Session**: one play session of a campaign, numbered from 1. Only the GM manages it.
- **Session status**: *In prep* or *Done*. A session starts in prep. The GM marks it done after play and may move it back. Every member sees the status.
- **Log**: the final record of a session. Members read it. Only the GM edits it.
- **Prep**: the GM-only text of a session. The GM plans in it and takes live notes in it during play.
- **Player log**: one player's recollection of a session. One per player per session. Every member reads every player log. Only its author writes it. The GM is not a player and has none.
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
- **Mention**: an inline @ link to another entry. It stores an ID and shows the current name.
- **Image**: an uploaded picture, converted to WebP. It stands alone, with no parent. The document stores its ID, never a URL.

## Access

- **Shared**: readable by all members. Editable by all members once the entry is revealed.
- **GM-only**: readable and editable only by the GM.
- **Player-private**: readable and editable by one player and the GM.
- **Hidden**: an entry not yet revealed to other players. Every entry starts hidden.
- **Revealed**: an entry its owner or the GM made readable by all members. The owner or the GM can hide it again.
- **Owner**: the member who created an entry. The owner and the GM read a hidden entry and manage it.
- **Archived**: removed from active lists, never deleted. The owner or the GM can restore it.
- **Restricted entry**: the label a reader sees for a link to an entry they cannot access.
- **Deleted entry**: the label an authorized reader sees for a link to an archived entry.
- **Preview as player**: a read-only page that shows a campaign the way a player sees it.
