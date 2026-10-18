# Sharing (task 24 part B): asynchronous export / import

Pause menu > Share. Files go to `user://exports/` (the window shows the real folder path). All files are plain JSON.

| Kind | Extension | Contents |
|---|---|---|
| Household | `.sim4household` | members (name, life stage, age, traits, look, skills, aspiration, key memories, career, birthday), relationships among members, parent links, Chronicle lines that mention them, small legacy stats |
| Town | `.sim4town` | a full save (`SaveLoad.snapshot`), the Chronicle lines, and an `inbox` of gifts and letters |
| Card | `.sim4card` | a family-history card (title, members, text lines, a few numbers); the window can also write a PNG |

## What happens on import
- **Household**: each member becomes a Story townie with a FRESH id (`Story.next_id`), on the roomiest of the six lots. Names are kept unless somebody here has the same name. Looks are kept where possible and rerolled (`GeneticsUnique.make_distinct`) until distinct from everyone in town. Relationships among the family are rebuilt; nobody else knows them (strangers). Skills, aspiration, memories and the history lines are kept in `townie.shared` and `ShareState.families`. A news line and a Chronicle note say "The X family moved to town." Limits: 40 townies, 12 imported families.
- **Town**: the validated save is written to a NEW empty slot (never over a used one) and loaded with the normal Load button. Its embedded `share` block is dropped; only the envelope's `inbox` is used.
- **Gifts**: a coin gift (max 500), an object from the allowlist in `data/share_schema.json` (placed next to the home mailbox, else listed as a keepsake) or a letter (max 500 characters). At most 6 items per file. `ShareExport.leave_gift` adds one to a town file. On loading the town, `ShareState.deliver_pending` hands everything over once: items leave the inbox, and a fingerprint is kept in `user://share_seen.json` so reloading the slot or importing the same file again never pays twice.

## Safety rules (all in `ShareValidate*` / `ShareClean` / `ShareFile`)
- Files are data only: JSON is parsed, never executed; only plain file names with the right extension are opened (no folders, `..`, drive letters); size is checked before reading (household 256 KB, town 32 MB, card 32 KB).
- The format and `version` are checked (newer or older than supported is refused). Unknown fields anywhere are refused.
- Every value is rebuilt from known fields: wrong types, NaN, inf are refused; numbers are clamped; counts and array sizes are capped; strings are capped, stripped of control characters, markup (`< > [ ] { }`), slashes and `..`; strings that point at `res://`, `user://`, `../` or drive paths refuse the whole file. Nesting depth and node count are capped.
- Ids in a file are only labels (`ref`) and are remapped; unknown traits, skills, aspirations, careers and objects are refused.
- Town saves are validated at the top level, systems list, folk and townie records and scanned everywhere (size, depth, numbers, strings); deeper sub-systems are loaded by the normal save loader (rough edge: not schema-checked field by field).

## Code map
`scripts/systems/share_*.gd`: `ShareClean` (primitives, caps from `data/share_schema.json`), `ShareValidate` (household, gifts), `ShareValidateTown`, `ShareFile`, `ShareExport`, `ShareImport`, `ShareState` (saved as `systems.share`), `ShareMail` (object gifts), `ShareCards`. UI: `scripts/ui/share_hub.gd` + `share_page_*.gd`. Tests: `tests/share_{household,hostile,town,ui}_test.gd` (+ `share_kit.gd`).
