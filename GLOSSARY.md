# Glossary

Domain terms for Atlas. Use these words in code and tests.

## People

- **Campaign**: one closed game with one GM and many players. Only members can access it.
- **GM**: the one person who runs a campaign. Use "GM", not "DM". Roles belong to a campaign, not to an account.
- **Player**: a member of a campaign who is not the GM.
- **Account**: a signed-in user. An account is not a player character.
- **Member**: the GM or a player of a campaign.
- **Invitation**: a reusable invite link to a campaign. It has no expiry and works until the GM revokes it. A campaign has at most one active invitation. Revoking stops future joins and keeps existing players.

## Content

- **Entry**: a named item in a campaign. Kinds: player character, NPC, creature, location, faction, item, note.
- **Player character**: an entry that always belongs to one player, even when the GM creates it.
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
- **Revision**: the counter of a section. A save must send the revision it read (`expected_revision`). A stale revision is rejected.
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
