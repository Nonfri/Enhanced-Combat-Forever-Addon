# Enhanced Combat Forever — Agent Context

## What this is

A World of Warcraft addon for the **WoW Forever** private server (client 1.60.1, build 70938, Interface `16001`). It provides:

1. **Dynamic nameplate range indicator** — a coloured dot beside the current target's nameplate showing whether the selected ability is in range (green), out of range (red), or unknown (grey).
2. **Rotation system** — ordered ability rows with per-row conditions. Highlights the next castable ability on the action bar as the player works through the sequence.
3. **Listeners** — independent condition-triggered highlights that fire outside the rotation order (e.g. "highlight Stealth whenever health drops below 25%").

## Client environment

- **Lua 5.1** inside a sandboxed WoW client. No standard I/O, no `require`, no file system.
- **Interface version**: `16001` (WoW Forever). APIs differ from retail and other private servers — always verify with the MCP `wow_api_search` tool before writing any API call.
- **TOC file**: `EnhancedCombatForever/EnhancedCombatForever.toc`. Every new Lua file must be added here.
- **Saved variables**: `EnhancedCombatForeverDB` per-character. Accessed via `addon.db` after `Core.lua` initialises it on `ADDON_LOADED`.

## Security model — the most important constraint

WoW Forever enforces a **taint** system and **secret values**:

- **`issecretvalue(value)`** — returns `true` for values the game considers protected in combat (health, power, range results, action info, etc.). **Always check before arithmetic or comparison.** Return `nil` (not `false`) when a value is unavailable so callers can wait rather than guess.
- **`AllowedWhenTainted` vs `AllowedWhenUntainted`** — some API functions can only be called from Blizzard's own (untainted) code. Addon code is tainted. Check `wow_api_search` for the `allowedWhenTainted` flag before calling any API.
- **`pcall` everything** — wrap every `C_Spell.*`, `C_UnitAuras.*`, `UnitHealth`, `GetActionInfo`, etc. in `pcall`. API availability is not guaranteed and errors propagate up to the event handler, breaking the frame.
- **Hostile target auras** — `C_UnitAuras` functions for `"target"` unit return `nil` for hostile targets in WoW Forever. There is no workaround. Do not attempt to read enemy debuffs.
- **`C_Spell.IsActiveSpell`** — returns a secret value in combat. Use event-based state tracking instead.
- **`C_Spell.IsAutoRepeatSpell`** — returns `false` for wand Shoot in WoW Forever. Unreliable; do not use.

## File map

| File | Responsibility |
|---|---|
| `Core.lua` | Addon bootstrap, `ADDON_LOADED` handler, SavedVariables init, nameplate range indicator frame, range polling, melee detection, `addon.db` |
| `Conditions.lua` | Condition type definitions, `EvaluateRotationCondition`, protected percent/seconds probing via `C_CurveUtil`, `ValidateCondition`, `CreateConditionControls` UI |
| `Rotations.lua` | Rotation profile data model, `SaveRotationProfile`, `GetActiveRotationProfile`, `CreateRotationsSettings` UI |
| `Listeners.lua` | Listener data model, `GetListenerSpell`, `CompleteCurrentListener`, cooldown gating, latch logic, `CreateListenersSettings` UI |
| `RotationHighlights.lua` | Action bar glow rendering, `currentSpell()` decision engine, Shoot toggle gate, post-cast wait, `UpdateRotationHighlights`, `BuildRotationReport`, `/ecfrotation` command |
| `Settings.lua` | Main settings panel, tab layout, manual ability selector, dynamic indicator toggle, `/ecf` command |
| `Debug.lua` | `/ecfdebug` live distance/range debug window, `DebugSample()` |
| `SpellInspect.lua` | `/ecfspell <id>` spell info dump for development |

## Key architecture patterns

### Condition evaluation
`addon.EvaluateRotationCondition(condition, ability)` returns:
- `true` — condition passes, ability should be highlighted
- `false` — condition fails, skip this row
- `nil` — result is unavailable (secret value, API error); **caller must wait, not skip**

### Rotation index
`RotationHighlights.lua` owns a module-local `index` (1-based). It advances via `index = index % #savedAbilities + 1` on a successful cast. `UpdateRotationHighlights(true)` resets to 1 (call on target change and profile switch).

### Shoot toggle gate
`START_AUTOREPEAT_SPELL` / `STOP_AUTOREPEAT_SPELL` events set/clear `autoRepeatActive`. When `true`, `currentSpell()` bypasses the normal rotation and returns the spell for the first `shootToggle` or `shootToggleOff` row, keeping the indicator locked on Shoot. On `STOP`, the index advances past the shoot row so the rotation resumes from the next ability.

### Listener latch
A listener fires once per condition transition (false→true). `state.latched = true` after the ability is cast. The latch clears when any condition returns `false` **or `nil`** — this prevents permanent latching when a condition oscillates through an unavailable state.

### Protected value probing
Raw health/power/percent values are secret in combat. `Conditions.lua` uses `C_CurveUtil.CreateCurve()` to probe thresholds without reading the raw number — the curve maps the secret value to a readable 0/100 output via `EvaluateRemainingDuration` / `UnitHealthPercent(unit, false, curve)`.

## Slash commands

| Command | File | Purpose |
|---|---|---|
| `/ecf` | `Settings.lua` | Open settings panel |
| `/ecfrotation` | `RotationHighlights.lua` | Print full rotation diagnostic report |
| `/ecfdebug` | `Debug.lua` | Toggle live range debug window |
| `/ecfspell <id>` | `SpellInspect.lua` | Dump spell info for development |

## Rules for writing code

1. **Always `pcall` WoW API calls.** No exceptions.
2. **Always `issecretvalue()` before using a value in arithmetic, comparison, or string formatting.**
3. **Return `nil` not `false` for unavailable results** — `nil` means "wait", `false` means "condition not met".
4. **Check `wow_api_search` before using any API.** Availability, taint status, and return types differ from retail.
5. **Never read hostile target auras.** `C_UnitAuras` on `"target"` always returns `nil` for enemies.
6. **No `table.unpack` in test files** — use `table.unpack or unpack` for Lua 5.1 compatibility in CI.
7. **Add new Lua files to the TOC** — the TOC validator CI check will catch omissions.

## Testing

```bash
# Run all Lua test suites (requires lua5.1)
lua5.1 tests/run_all.lua

# Run deploy script tests
npm test
```

Tests run in isolated subprocesses. Each suite in `tests/` stubs the WoW API globally and loads addon files via `loadfile("EnhancedCombatForever/X.lua")("EnhancedCombatForever", addon)`. Run from the **repository root**.

## CI (GitHub Actions)

Four jobs on every PR and push to `main`:
- **Lua unit tests** — `lua5.1 tests/run_all.lua`
- **Luacheck** — static analysis of `EnhancedCombatForever/`
- **TOC file integrity** — verifies all TOC-listed files exist
- **Deploy script tests** — `npm test`

## MCP tools available

The `hated-wow-mcp` server is configured for `WOW_DEFAULT_FLAVOR=forever`. Key tools:
- `wow_api_search` — look up any API function before using it
- `wow_ui_grep` — search Blizzard's shipped UI source
- `wow_lua_lint` — lint addon Lua for removed/tainted APIs
- `wow_api_event_search` — find events by name or pattern

Always run `wow_lua_lint` on new Lua before considering it finished.
