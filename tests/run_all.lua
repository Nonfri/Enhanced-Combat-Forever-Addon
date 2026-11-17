-- Test runner: execute from the repository root with `lua tests/run_all.lua`
-- Each suite runs in its own subprocess so global state cannot bleed between tests.
local suites = {
    "tests/conditions.lua",
    "tests/rotations.lua",
    "tests/listeners.lua",
    "tests/rotation_highlights.lua",
    "tests/range_indicator.lua",
    "tests/settings_validation.lua",
    "tests/spell_inspection.lua",
}

local lua = arg and arg[-1] or "lua"
local passed, failed = 0, 0
for _, path in ipairs(suites) do
    local ok = os.execute(lua .. " " .. path)
    -- os.execute returns true on Lua 5.2+, 0 on Lua 5.1
    if ok == true or ok == 0 then
        passed = passed + 1
    else
        io.stderr:write("FAIL: " .. path .. "\n")
        failed = failed + 1
    end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
