# RaidFormer (WotLK 3.3.5a)

Forms a raid for you: players whisper their GearScore and spec, RaidFormer invites them,
inspects them when they come close, checks GearScore + talents, kicks those who don't
qualify and keeps announcing what the raid still needs.

Fully self-contained: no Ace3, no GearScoreLite needed (GearScore formula is built in and
produces the same numbers as GearScoreLite).

## Install
Copy (or symlink) the `RaidFormer` folder into `World of Warcraft/Interface/AddOns/`.

## Quick start
1. `/rf` (or left-click the minimap button) to open the window. It has three tabs (bottom left):
   **Raid** (the dashboard you watch while forming), **Formation** and **Settings**.
2. **Settings** tab: pick raid, 10/25, Normal/Heroic, your own role (Auto/Tank/Healer/DPS), min
   GearScore, one or more channels (plus Guild/Yell), seconds between posts and extras via
   the buttons `B+O+P RES`, `BOE RES`, `BOE+P RES`, `Link best achiev`.
   The preview shows exactly what will be posted, e.g.
   `LFM TOC25N - GS 5.3k+ - Need: 2 heal, 5 dps - B+O+P RES - fast run - /w spec + GS`.
   "Announcement style" (next to the preview) picks the look: Clean dashes (default),
   Raid icons (`{skull} LFM TOC25N {skull} Need: ... {skull} ...`, icon selectable), Brackets
   (`[TOC25N] LFM - [Need: ...] - ...`) or Need first (`TOC25N needs 2 heal, 5 dps - ...`).
   "Free text" (optional, up to 80 characters) goes right before `/w spec + GS`. If the line gets
   longer than 255 characters, the need list is shortened (ending in "...") and your free text stays.
   Automatic whispers start with `[RaidFormer]` so players can tell an addon is answering;
   LFM posts, /raid messages and raid warnings don't.
   Once 5 or more spots are taken the raid count is added automatically, for any raid size:
   `LFM TOC25N [18/25] - GS 5.3k+ ...` (no count below 5); it follows people joining and leaving.
   What's needed: classes from your formation list are only named once they're all that's
   left. Roles are counted with their reserved needs included; a role's count turns into its
   names (e.g. `rsham`) when every open spot of it is reserved, and when every open spot in the
   raid is reserved exactly the remaining needs are listed. Open roles are bundled: every role
   open -> `Need: all`; melee and ranged both open -> one `dps` count. Over a raid:
   `Need: all` -> `Need: 6 heal, 17 dps` -> `Need: rsham, 17 dps` -> `Need: rsham, rog`.
   Counts never go above the free spots in the raid: 8/10 in with hpal and rdru still on the
   formation list reads `Need: hpal, rdru`, not `4 heal, 13 dps`. When more classes are on the list
   than there are spots, any of them will do: 1 heal spot with hpal + rdru needed reads `hpal/rdru`
   (2 spots, 3 needs: `2 of hpal/rdru/disc`), and whichever whispers first gets in - other healers
   are still refused. Needs for a role that's already full aren't asked for.
   Specs are abbreviated (rog, rsham, hpal, ppal, demo, hunt, boomy, rdru, disc, fmage,
   SPriest, ...) and players can use the same abbreviations when whispering. With several channels the message goes
   out to each in turn with a random 0.8-1.2s pause between them.
3. **Formation** tab: tank/healer/melee/ranged/any-DPS counts, class/spec needs (e.g. 1x Shaman -
   Restoration, or any Shaman for Bloodlust) and class/spec caps as chips with -/+/x. Add them by
   clicking a class icon (pick Need or Cap first, then the spec). A warning shows when needs don't
   fit the role slots.
   **Any DPS** spots are for when you don't mind melee or ranged: they go to whichever DPS comes
   first, and the LFM line asks for `1 dps` (e.g. `Need: 1 rdps, 1 dps` when melee is full).
   **Caps** take a class and optionally a spec: `Druid max 3` plus `Druid - Restoration max 1`
   refuses a 2nd rdru (`max 1 rdru`) while other druids are still welcome.
   Save your favourite setups as presets. A loaded preset (or anything you edit: roles, needs,
   caps, min GS) is your baseline: changing raid, size or difficulty afterwards keeps it, only
   the raid tag changes. If the role counts added up to the old size, they're fitted to the new
   one (25 -> 10: 2 tank, 5 heal, 8 melee, 10 ranged becomes 2/2/3/3; needs, caps and GS stay),
   keeping room for the needs (3 healer specs on the list -> at least 3 heal). If the needs don't
   fit the formation you get a warning in chat (on Start and after a size change). "Load recommended" switches back to the recommended setup, which then
   follows raid changes again. The "Based on: ..." line shows which one you're on.
4. Click **Start** (title bar, or right-click the minimap button). Watch the **Raid** tab:
   - a progress bar (`TOC25N 18/25`) and what's happening (`next post 23s`, `Raid full`)
   - role chips (`2/2`, `M 5/6`, ...) and need chips (green = in, red = still missing)
   - the LFM line as it's posted right now (click it to edit it in Settings)
   - a yellow line when something is off: not leader/assist, needs don't fit, role counts don't add
     up, no channel or a channel you're not in
   - the roster in sections: In raid, Waiting for inspect, Invited, History (folded; click a section
     to fold/unfold, `clear` forgets the history). Hover a player for Insp / Accept / Kick and the
     details, right-click for the full menu (Accept, Inspect again, Kick, Whisper, Set spec), click
     the spec to change it.
5. **Mini bar:** close the window while running and a small bar takes over: raid count, what's
   needed, next post, Start/Stop, Post and Open. Drag it anywhere; Settings > Interface sets when
   it shows (running / always / never), locks it, and scales the whole UI.

## How applicants are handled
| Step | What happens |
|---|---|
| Whisper `5.6k resto shaman` | Parsed (many formats: `5,6k`, `5k6`, `5600`, `rsham`, `rpal`, `pr heal`, `sp`, `mm`, `mm hunt`, `bear`, `dk tank`, typos like `shamman`, ...) |
| Two specs (`enh 6,3/ resto 5,7`, `resto 5.7 or enh 6.3`, `ret 5.8k prot 5.2k`) | Each spec is an option with its own GS (`resto` takes the class from the other half: enh -> shaman). The one the raid needs most is picked: an open spec need first, then a class need, then the role with most spots open. The second spec shows on the Raid tab (`rsham/enh`); if they're still in its talents at inspect, they count as the picked spec |
| You change a player's spec (click the spec on the Raid tab, e.g. fwar -> pwarr) | Counts and the LFM line follow right away; your pick also wins over talents at inspect |
| Only class or role (`5.6k shaman`, `5.6k heal`) | Invited with a spec the raid can still use; the inspect decides the real one |
| Nothing recognised (`5.6k qpal`) | Asked for class/spec; the word is saved - see it with `/rf unknown`, teach it with `/rf alias qpal ret` |
| GS below minimum / role full / slot reserved | Polite whisper with the reason and what is still needed |
| Accepted | Invited - no whisper (tell them where to go with "RW on join", e.g. `g1 vh`) |
| Joins the raid | Optional raid warning, e.g. `g1 vh` (Settings: "RW on join"); joins within 10s share one warning, /raid if you're not leader/assist |
| In range | Inspected automatically, real GS and talent tree checked |
| GS too low or talents don't match | Auto kick on: whisper with the reason + kick. Auto kick off: no whisper, you're told in chat and they stay - Kick or Accept them on the Raid tab |
| Inspected after the raid filled up (you added people yourself while they were on the way) | Their slot was approved for their spec at invite: if the inspect shows that spec, they stay - only GS, or a spec that differs and doesn't fit, can remove them |
| Inspected after you pressed Stop | Never kicked or whispered; a failed check is only told to you in chat |
| Invited but whispers again (missed the invite popup) | Invited again, at most every 30s |
| Doesn't come within the timeout | Warned 60s before, then kicked (Auto kick off: they stay, no "removed" whisper, you're told in chat) |
| "Require inspect" off (Settings) | Whoever joins is accepted at their whispered word: no inspect, no GS check, no timeout. Turning it back on only affects players who join afterwards |
| "Remind to inspect" off (Settings) | No "come to me for inspect" warning and nobody is removed for not showing up; they stay in the queue until you inspect or remove them |
| Joined without whispering | Inspected too; spec taken from talents |
| Anyone you (or an assist) invite yourself - friends, a refused/removed player you let in anyway | Holds a slot from the moment you invite them. Trusted: counted, inspected for their spec only, never timed out or removed |
| Rejected but still in the raid (e.g. auto kick off) | Still takes a slot, counted with their inspected spec |
| You press "Insp" on the Raid tab (hover a player) | Inspected again to confirm GS - also players you let in yourself and with "Require inspect" off. Moved to the uninspected group right away (swapping with someone already inspected if it's full; not with Manual groups); the result is printed in chat: `Name inspected: GS 5612, rsham - accepted` |
| Spec unknown or wrong (friend never came to inspect, bear vs cat) | Click the spec on the Raid tab and pick the right one; for players you let in your choice beats talents |
| Removed for low GS and whispers again within 5 min | Told their inspected GS, not invited again yet |
| Whispered spec/class differs from the inspect | Real class/spec is used: kept if it still fits (counted as ret), removed if not. Tick "Kick wrong spec claims" to always remove them |

**Inspect queue:** one inspect at a time (WoW only keeps data for one target), first come
first served by the moment each player got in range (the Raid tab shows "In queue #N").
Once someone has arrived they can't time out while waiting in line.
Only whispers that explain a refusal or removal are sent (min GS, spots full, class/spec not
understood, removed + reason, inspect timeout warning). Invites and accepts are silent.
If another addon (e.g. GearScoreLite on mouseover) inspects someone else in the middle of
ours, that result is thrown away and the player is inspected again.

**Low GS on first inspect (transmog / stale data):** a reading below the minimum is never
final. The player is inspected again ~2s later and the highest GS counts; a rejection needs
two low readings with identical gear (a third look is taken if the gear changed).

**Timeout / warning:** both adjustable in the Settings tab ("Inspect timeout", "Warn before";
0 = no warning). The Raid tab shows the time left.

**Raid groups:** `Raid groups: [Forming] [Final] [Manual]` at the bottom right of the window (needs leader/assist), the
active one lit. Nothing is moved until you press Forming or Final.
- **Forming groups** - RaidFormer controls the groups: you and uninspected players in the
  uninspected group (default 1, overflow into group 8), everyone else (inspected, or let in by
  you) in group 2 and up. It puts back players you move yourself while it is active.
- **Final groups** - sorts the raid once, then the groups are yours until you press Forming
  again. Layout: tanks with melee, then ranged, then healers. In 3.3.5 almost every buff is
  raid-wide (totems' stat buffs, Moonkin Aura, Leader of the Pack, Bloodlust, auras), so the
  sort spreads the effects that still only reach one party: Shadow Priest (Vampiric Embrace)
  with ranged, Subtlety Rogue (Honor Among Thieves) with melee, and one Holy Priest / Resto
  Shaman (Prayer of Healing, Healing Stream / Tremor / Cleansing totems) per fighting group.
- **Manual** - full control: RaidFormer lets go of the groups and never moves anyone, not even
  when you press Insp, until you press Forming or Final again. Kept over /reload. (Kicks and
  raid warnings have their own switches in Settings: "Auto kick" and "RW on join".)
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
