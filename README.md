# RaidFormer (WotLK 3.3.5a)

Forms a raid for you: players whisper their GearScore and spec, RaidFormer invites them,
inspects them when they come close, checks GearScore + talents, kicks those who don't
qualify and keeps announcing what the raid still needs.

Fully self-contained: no Ace3, no GearScoreLite needed (GearScore formula is built in and
produces the same numbers as GearScoreLite).

## Install
Copy (or symlink) the `RaidFormer` folder into `World of Warcraft/Interface/AddOns/`.

## Quick start
1. `/rf` (or left-click the minimap button) to open the window.
2. **Setup** tab: pick raid, 10/25, Normal/Heroic, your own role (Tank/Healer/DPS), min
   GearScore, one or more channels (plus Guild/Yell), seconds between posts and extras via
   the buttons `B+O+P RES`, `BOE RES`, `BOE+P RES`, `Link best achiev`.
   The preview shows exactly what will be posted, e.g.
   `LFM TOC25N GS 5.3k+ need: rog, rsham, ppal, demo, hunt, 1 heal, 7 mdps / B+O+P RES / fast run - /w spec+gs`.
   "Free text" (optional, up to 80 characters) goes right before `/w spec+gs`. If the line gets
   longer than 255 characters, the need list is shortened (ending in "...") and your free text stays.
   Automatic whispers start with `[RaidFormer]` so players can tell an addon is answering;
   LFM posts, /raid messages and raid warnings don't.
   "Show 23/25 in the LFM line" (optional) puts the current raid count after the raid tag:
   `LFM TOC25N 23/25 GS 5.3k+ ...`; it follows people joining and leaving.
   Open roles are bundled: every role open -> `need: all`; melee and ranged both open ->
   one `dps` count (e.g. `2 heal, 7 dps`).
   Specs are abbreviated (rog, rsham, hpal, ppal, demo, hunt, boomy, rdru, disc, fmage,
   SPriest, ...) and players can use the same abbreviations when whispering. With several channels the message goes
   out to each in turn with a random 0.8-1.2s pause between them.
3. **Formation** tab: tank/healer/melee/ranged counts, class/spec needs (e.g. 1x Shaman -
   Restoration, or any Shaman for Bloodlust) with -/+ counts per row, quick-add buttons for
   common specs, a warning when spec needs don't fit the role slots, and class caps.
   Save your favourite setups as presets. A loaded preset (or anything you edit: roles, needs,
   caps, min GS) is your baseline: changing raid, size or difficulty afterwards keeps it, only
   the raid tag changes. "Load recommended" switches back to the recommended setup, which then
   follows raid changes again. The "Based on: ..." line shows which one you're on.
4. Click **Start** (or right-click the minimap button). Watch the **Roster** tab.

## How applicants are handled
| Step | What happens |
|---|---|
| Whisper `5.6k resto shaman` | Parsed (many formats: `5,6k`, `5k6`, `5600`, `rsham`, `rpal`, `pr heal`, `sp`, `mm`, `mm hunt`, `bear`, `dk tank`, typos like `shamman`, ...) |
| Two specs (`enh 6,3/ resto 5,7`, `resto 5.7 or enh 6.3`, `ret 5.8k prot 5.2k`) | Each spec is an option with its own GS (`resto` takes the class from the other half: enh -> shaman). The one the raid needs most is picked: an open spec need first, then a class need, then the role with most spots open. The second spec shows in the Roster (`rsham/enh`); if they're still in its talents at inspect, they count as the picked spec |
| You change a player's spec (click the spec in the Roster, e.g. fwar -> pwarr) | Counts and the LFM line follow right away; your pick also wins over talents at inspect |
| Only class or role (`5.6k shaman`, `5.6k heal`) | Invited with a spec the raid can still use; the inspect decides the real one |
| Nothing recognised (`5.6k qpal`) | Asked for class/spec; the word is saved - see it with `/rf unknown`, teach it with `/rf alias qpal ret` |
| GS below minimum / role full / slot reserved | Polite whisper with the reason and what is still needed |
| Accepted | Invited - no whisper (tell them where to go with "RW on join", e.g. `g1 vh`) |
| Joins the raid | Optional raid warning, e.g. `g1 vh` (Setup: "RW on join"); joins within 10s share one warning, /raid if you're not leader/assist |
| In range | Inspected automatically, real GS and talent tree checked |
| GS too low or talents don't match | Whisper with reason + kick (if Auto kick is on) |
| Doesn't come within the timeout | Warned 60s before, then kicked |
| "Require inspect" off (Setup) | Whoever joins is accepted at their whispered word: no inspect, no GS check, no timeout. Turning it back on only affects players who join afterwards |
| "Remind to inspect" off (Setup) | No "come to me for inspect" warning and nobody is removed for not showing up; they stay in the queue until you inspect or remove them |
| Joined without whispering | Inspected too; spec taken from talents |
| Anyone you (or an assist) invite yourself - friends, a refused/removed player you let in anyway | Holds a slot from the moment you invite them. Trusted: counted, inspected for their spec only, never timed out or removed |
| Rejected but still in the raid (e.g. auto kick off) | Still takes a slot, counted with their inspected spec |
| Spec unknown or wrong (friend never came to inspect, bear vs cat) | Click the spec in the Roster tab and pick the right one; for players you let in your choice beats talents |
| Removed for low GS and whispers again within 5 min | Told their inspected GS, not invited again yet |
| Whispered spec/class differs from the inspect | Real class/spec is used: kept if it still fits (counted as ret), removed if not. Tick "Kick wrong spec claims" to always remove them |

**Inspect queue:** one inspect at a time (WoW only keeps data for one target), first come
first served by the moment each player got in range (the Roster tab shows "In queue #N").
Once someone has arrived they can't time out while waiting in line.
Only whispers that explain a refusal or removal are sent (min GS, spots full, class/spec not
understood, removed + reason, inspect timeout warning). Invites and accepts are silent.
If another addon (e.g. GearScoreLite on mouseover) inspects someone else in the middle of
ours, that result is thrown away and the player is inspected again.

**Low GS on first inspect (transmog / stale data):** a reading below the minimum is never
final. The player is inspected again ~2s later and the highest GS counts; a rejection needs
two low readings with identical gear (a third look is taken if the gear changed).

**Timeout / warning:** both adjustable in the Setup tab ("Inspect timeout", "Warn before";
0 = no warning). The Roster tooltip shows the time left.

**Raid groups:** two buttons on the Roster tab (needs leader/assist). Nothing is moved until
you press one.
- **Forming groups** - RaidFormer controls the groups: you and uninspected players in the
  uninspected group (default 1, overflow into group 8), everyone else (inspected, or let in by
  you) in group 2 and up. It puts back players you move yourself while it is active.
- **Final groups** - sorts the raid once, then the groups are yours until you press Forming
  again. Layout: tanks with melee, then ranged, then healers. In 3.3.5 almost every buff is
  raid-wide (totems' stat buffs, Moonkin Aura, Leader of the Pack, Bloodlust, auras), so the
  sort spreads the effects that still only reach one party: Shadow Priest (Vampiric Embrace)
  with ranged, Subtlety Rogue (Honor Among Thieves) with melee, and one Holy Priest / Resto
  Shaman (Prayer of Healing, Healing Stream / Tremor / Cleansing totems) per fighting group.
- **Stop** also hands the groups back to you.

**Slot reservation:** if the formation requires e.g. Bloodlust and only one ranged spot is
left, a mage is refused and an elemental shaman accepted, so the raid never fills up
without its requirements.

Your own character counts as a raid member (spec auto-detected, or set "My spec").

## Commands
`/rf` window · `/rf start` · `/rf stop` · `/rf post` · `/rf status` · `/rf clear`

## Notes
- You must be raid leader or assistant for invites/kicks.
- Inspect range is ~28 yards (same as trade).
- Mind your server's rules on channel spam; the minimum post interval is 30 seconds.
