# Enhanced Combat Forever

A WoW Forever addon, initially targeting client **1.60.1 / build 70938 / Interface 16001**.

Version 0.1 adds an ability range indicator beside the current target's overhead nameplate.
It follows both click and Tab targeting. Green means in range, red means out of range,
and gray means the client cannot provide a usable range result. No visible target
nameplate means no indicator. Enable the appropriate nameplates in the game's settings.

## Installation

1. Copy the `EnhancedCombatForever` folder into your Forever client's
   `_forever_/Interface/AddOns/` directory.
2. Confirm the resulting path is
   `_forever_/Interface/AddOns/EnhancedCombatForever/EnhancedCombatForever.toc`.
3. Restart the game if installing for the first time, then enable **Enhanced Combat Forever**
   in the character selection AddOns list.
4. In game, enter `/ecf`, or open Settings > AddOns > Enhanced Combat Forever.

## Deploy from the repository

Requires Node.js 20+; no npm dependencies or `npm install` step are needed.

Set `addonsPath` in the local `deploy.config.json` to your existing game's
**Interface/AddOns directory**, without the `EnhancedCombatForever` suffix:

```json
{
  "addonsPath": "/mnt/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
}
```

Use your actual installation path. When running in WSL, use `/mnt/c/...` for a
Windows C: drive (or `/mnt/d/...` for D:). When running Node on Windows directly,
use a path such as `C:/Games/World of Warcraft/_forever_/Interface/AddOns`.
`deploy.config.json` is ignored by Git so your machine's path stays local.
On a fresh checkout, copy `deploy.config.example.json` to `deploy.config.json` first.

Preview the destination:

```bash
npm run deploy -- --dry-run
```

Copy the addon:

```bash
npm run deploy
```

This creates or updates `EnhancedCombatForever` under the configured directory,
copying only the addon folder. It overwrites matching addon files and preserves
other addons and extra destination files; it does not remove files deleted from
the source. The configured AddOns directory must already exist. Restart WoW for
the first installation; use `/reload` after later deployments.

Run deployment tests with `npm run test:deploy`. Tests deploy into a temporary
directory and do not use your configured game path.

## Settings

The **Indicators** tab below the addon description contains the ability and
nameplate indicator controls.

The **Rotations** tab contains custom rotation profiles:

1. Click **Add rotation profile**, enter a unique name, then click **Create**.
2. Click a profile name under **Profiles** to expand or collapse it.
3. Click **Add ability** to add a row and enter an ability name.
4. Use the up/down arrows to change the order. Arrows at list boundaries are disabled.
5. Click **Save** below that profile's list to save its ability names and order.

**Delete** beside a row's arrows removes that ability and its condition from the
draft, closes the gap, and renumbers the remaining rows. Save applies the deletion
to the profile and restarts the active rotation with the updated order. Deleting
all rows leaves an empty profile.

For rogues and druids, add an ability row and select **Combo points** from its
condition selector. Enter the ability (for example, Eviscerate) and a threshold
from 1 to 5. When that row is reached in rotation order, combo points at or above
the threshold select its ability; otherwise the row is skipped. Conditional rows
can be reordered with ordinary abilities and are saved with the profile. Draft
condition edits do not affect the active rotation until saved.

For a simple finisher loop, place **combo points >= 5 → Eviscerate** first and
**Sinister Strike** second. Below five points, the finisher row is skipped and
Sinister Strike is highlighted. After each successful Sinister Strike, the loop
returns to the condition and checks again. Conditions are ordered checks, not
global priority overrides. If every row is conditional and none passes, nothing
glows and Dynamic Indicator is gray. If combo-point data is unavailable or
restricted, the rotation waits at that condition instead of guessing.

Rotations and Listeners share one condition list and editor: **Always**, **Ability
in range**, **No target**, the **Out of combat** variants, **Player health (%)**,
**Player health (number)**, **Player mana (%)**, **Player rage (%)**, **Player
energy (%)**, **Buff remaining (seconds)**, and (for rogues/druids) **Combo points**.
New **Add ability** rows default to **Ability in range**;
existing saved conditions are preserved. Choose **Ability in range** on an existing Throw
row to use it only when Throw can reach the current target; otherwise the rotation
skips to the next row. The condition checks that row's ability and supports both
ranged and melee abilities using the same range rules as the nameplate indicator.
An unavailable or restricted range result waits at the row, rather than treating
unknown as out of range. Range checks do not test cooldowns, resources, or facing.

Use **Add ability** for all new rows and choose the desired condition on that row.
Saved combo-point profiles remain compatible. More game mechanics can be added as
additional condition types. This feature does not cast abilities automatically.

**Out of combat** selects an ability only while the player is not in combat;
otherwise that row is skipped. Put Stealth or Prowl first with this condition for
an opening reminder. This condition is available to all classes and requires a living attackable target
for action-bar glows. Leaving combat restarts the rotation at its first row. The
condition tests combat state only; it does not check whether stealth is already active.

Use **Out of Combat - Toggle on** for a Stealth/Prowl reminder that stops once
the ability is active. **Out of Combat - Toggle off** selects the ability only
when it is currently active, to remind you to turn it off. Both conditions are
false in combat and require a living attackable target. Stance/form buttons use their
active-state flag; other toggled spells use `C_Spell.IsActiveSpell`. Unknown or
restricted toggle state waits instead of suggesting the wrong action. Existing
**Out of combat** rows keep their original behavior; select Toggle on and save
to update an existing Stealth row.

Click **Activate** beside a profile name to select it as the character's active
rotation profile. Its button changes to **Active** and is disabled. Activating a
different profile re-enables the previous profile's button. The selection persists
with your per-character settings. Activation uses the saved list; it does not save
draft edits or change whether the profile is expanded.

With an active profile and a living, attackable target, the current ability in
its saved rotation gets a yellow Blizzard proc-style glow on matching visible
action buttons. Only the current entry is highlighted. A successful player cast
of that ability advances to the next entry, looping after the final entry. Other
casts, failed casts, and pet casts do not advance the sequence. Changing targets,
activating a profile, or saving the active profile restarts at the first entry.
After a matching successful cast, a 0.2-second settling pause lets combo points
and other resource updates arrive before evaluating the next step. During that
pause the rotation glow clears and Dynamic Indicator is gray. Changing targets
or profiles cancels the old pause.

Matching uses spell IDs and localized names across ranks. Blizzard action bars
and buttons registered with Blizzard's action-button registry are supported,
along with Blizzard's stance/form/stealth bar. Stance buttons are matched using
the spell IDs returned by `GetShapeshiftFormInfo`; Stealth does not need to be
duplicated on a regular action bar. `/ecfrotation` includes stance button matches.
Spell macros match the spell currently reported by the client. An ability absent
from the bar or unresolved waits at that step. Glows indicate sequence order,
not cooldown, resource, or range readiness. Native proc alerts retain their state.
Restricted action or target data is skipped. Live-client combat behavior still
needs testing.

Profiles are stored per character. Draft edits survive collapsing profiles and
switching tabs, but must be saved before reloading or logging out. Profile creation
saves an empty profile immediately. Blank names and duplicate profile names are
rejected. Ability rows must contain names to save; names are stored as entered
(with surrounding spaces removed). This editor stores ordered lists and provides action-bar sequence guidance; it does
not cast abilities automatically.

Enter a learned ability's localized name or spell ID. Click **Check ability** to
see whether the character has learned it and whether it exposes a range check.
The result appears beside the button. Click **Save** to activate that ability;
checking alone does not change the active selection. Until an ability is explicitly
saved, the indicator stays gray. Auto Shot can be selected by name or spell ID 75. Size and horizontal/vertical offsets are configurable. Positive
gap values move the dot farther left of the bar; positive vertical offsets move up. Settings are saved
per character when you log out or reload the UI. Reset clears the ability selection (returning to gray) and restores default placement.
Existing users must save their ability once after this update to activate range colors.

The dot anchors to the left edge of the target's health bar, centered vertically.
The default gap is 8 pixels. This keeps it away from the name and aura icons above
that bar. Custom nameplate addons without Blizzard's health bar fall back to the
health bar container or nameplate frame and may require adjusting the offsets.
It does not alter Blizzard's nameplate settings.

## Listeners

Numeric conditions (combo points, health thresholds, Mana, Rage, and Energy) have a comparison
operator and value: **Greater than (>)**, **Less than (<)**, **Equal to (=)**,
**Greater than or equal to (>=)**, or **Less than or equal to (<=)**. For example,
`Player health (%) <= 30` or `Player health (number) < 500`. Both health conditions
measure **the player**, not the target. Percentage thresholds accept values from
0 to 100, including all three power conditions; raw health accepts nonnegative whole numbers. Combo points accept whole
numbers from 1 to 5. Boolean conditions do not show numeric operator/value fields.

**Buff remaining (seconds)** checks the player buff produced by that row's own
ability. A missing or expired buff counts as zero seconds, so the default `< 5`
condition reminds the player shortly before expiration and continues to remind
after it expires. Protected aura durations use the same engine-evaluated threshold
gate as protected health and power values. The listener cooldown gate still applies.

Old combo-point conditions retain their >= meaning. Both editors use the same
validation, operators, and available class-specific choices. Health is checked
without prediction. Percentage conditions use Forever's dedicated
`UnitHealthPercent` API. Mana, Rage, and Energy use `UnitPowerPercent` with their
explicit power type. When a percentage result is protected, an engine-evaluated curve
answers only the configured threshold question without exposing the exact value.
Health and power-change events refresh guidance. If values
are restricted/unavailable (which can happen in the client), conditions wait;
the addon does not calculate or guess with those values. Protected percentage
operators use 0.1% threshold resolution.

In the **Listeners** tab, click **Add listener**, enter a learned ability name or
spell ID, and add one or more conditions. Select each condition and set its value
where needed. **All** conditions on a listener must be met (AND). Click **Save**
to apply its ability, conditions, and Enabled checkbox; drafts do not affect
guidance. Conditions can be deleted individually, and listeners can be deleted
or disabled. Settings are saved per character.

The first enabled listener whose conditions match owns the glow and Dynamic
Indicator until you successfully cast that ability. Listeners work without an
active rotation profile. When a rotation is active, its index is preserved and
resumes after the usual 0.2-second settling pause. Unrelated casts do not advance the
paused rotation. A listener ability on cooldown is skipped automatically; the
global cooldown is ignored, and charge-based abilities remain eligible while at
least one charge is available. A listener must have its conditions become false before it can
trigger again, avoiding a permanent highlight loop. If multiple listeners are
ready, creation/list order determines priority; an active listener is not replaced
by another one until completed.

Listeners reuse the existing condition types, including class-specific combo
points and toggle states. Health, Mana, Rage, and Energy listeners can trigger without a target unless
they also use **Ability in range**, which requires a living attackable target.
Unknown/restricted condition data cannot trigger one.
Changing targets, activating/saving a rotation, or saving/deleting listeners resets
listener state. A triggered listener remains selected until its cast succeeds or
the context is reset, even if its original trigger conditions change meanwhile.
`/ecfrotation` shows every saved listener, its enabled/target/active/latched state,
each condition result, experimental `>=` health curve-probe result, and visible
action-button matches for troubleshooting. The curve probe is diagnostic only and
does not affect guidance until verified on the live Forever client.

## Range behavior and limitations

Enable **Dynamic Indicator** in the Indicators tab to make the nameplate dot
follow the current ability in the active rotation, in sync with the action-bar
glow. The checkbox takes effect immediately and is saved per character. It
overrides the manual ability selection, which is retained for when dynamic mode
is turned off. All controls below the Dynamic Indicator checkbox are hidden while
enabled and restored when unchecked. Existing size and position values still
apply to the dot. Without a usable
current rotation ability (including no active profile, an empty list, an unknown
ability, or an unavailable range check), dynamic mode shows gray. It does not
fall back to the manual ability. Melee detection applies to rotation abilities
in the same way as manually selected abilities. Reset disables dynamic mode.

The addon uses Forever's spell-range API, range-change events, and a throttled
0.15-second fallback while the indicator is visible. It does not estimate yards.
Green describes range only, not cooldowns, resources, facing, or line of sight.
Abilities with a tooltip header label of **Melee Range**, or an activation label
containing **Next melee**, use main-hand melee swing reach. Detection checks both
text columns and does not inspect descriptions or maintain an ability-name list.
Client localized labels are used when available, with English labels as fallback.
If the swing API cannot answer, ordinary melee abilities use their own range check;
next-swing abilities use another learned ability with a Melee Range label found
in the player's spellbook. If neither check answers, the indicator is gray.
Missing tooltip data also leaves the indicator gray until the data loads.
Unavailable, unknown, and secret range values display gray. Minimum-range behavior
depends on what the client reports for the chosen ability.

The API reference was checked through the WoW MCP server. Its Forever API index was
synced November 1, 2026; actual behavior in build 70938 still needs in-game validation.

## Validation

### Live range debugging

Use `/ecfrotation` to copy a rotation troubleshooting report with the saved
profile, row conditions and results, current step, combat state, and visible
action-button spell matches. Use it while the unexpected highlight behavior
is happening. It shares the copyable report window with `/ecfspell`.

Use `/ecfspell Raptor Strike` (or any localized ability name/spell ID) to inspect
the client's spell metadata, description, subtext, and tooltip lines in a
scrollable, copyable window. `/ecfspell` alone inspects the saved ability.
Click the report and press Ctrl+A, Ctrl+C to copy it. This captures client data
for investigation; it does not automatically classify an ability or change its
range check. If text is still loading, run the command again.

After deploying and reloading, enter `/ecfdebug` to open a movable debug window.
It samples automatically every 0.1 seconds while open and running. It shows
distance in yards only when `UnitDistanceSquared` returns a valid, readable
result; otherwise it explicitly shows unavailable or restricted. Auto Shot
and main-hand melee range are shown separately. Both out of range is ambiguous:
it does not prove that the target is in the hunter dead zone.

Range-state transitions and changes in whole-yard distance bands are recorded
in a rolling 60-entry history; the latest eight entries appear in the window.
Target changes are marked so results from different targets are not confused.

- `/ecfdebug pause` freezes the window and history for review after combat.
- `/ecfdebug resume` resumes sampling.
- `/ecfdebug clear` clears history and resets elapsed time.
- `/ecfdebug dump` prints the history to chat.
- `/ecfdebug` toggles visibility; hiding stops sampling.

The debug history stays in memory until a UI reload or logout. It does not
change the nameplate indicator or automatically classify the dead zone.
Sample-handling tests: `npx --yes --package=fengari-node-cli fengari tests/debug_sample.lua`.

The WoW MCP linter and TOC validator check client compatibility. Mocked behavior tests
cover range states, target switching, plate removal/reuse, polling, and spell changes:

```bash
lua tests/range_indicator.lua
```

If Lua is unavailable but Node is installed:

```bash
npx --yes --package=fengari-node-cli fengari tests/range_indicator.lua
```

In game, test on a character that knows Auto Shot:

- Enable enemy nameplates, select Auto Shot in `/ecf`, and approach/leave its range.
- Check the dot turns green/red, including any close-range restriction the client reports.
- Switch targets using both click and Tab; clear the target and let plates disappear.
- Repeat while in combat and check that an unavailable result stays gray.
- Change ability, size, and offsets; use `/reload` to confirm the settings persist.
- Check placement with any custom nameplate addon you use.

These tests cannot prove live-client combat restrictions or ability-specific behavior;
report any Lua error and the situation that triggered it.

Clearing the target stops rotation glows and resets the order. All existing
conditions, including Out of Combat toggles, require a living attackable target.
Use the explicit **No target** condition to allow a row to highlight only while
nothing is selected. Targeting an enemy skips that row and resumes normal guidance.
