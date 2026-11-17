-- Test runner: execute from the repository root with `lua tests/run_all.lua`
-- Each suite runs in its own isolated chunk via loadfile so globals don't bleed.
local suites = {
    "tests/conditions.lua",
    "tests/rotations.lua",
    "tests/listeners.lua",
    "tests/rotation_highlights.lua",
    "tests/range_indicator.lua",
    "tests/settings_validation.lua",
    "tests/spell_inspection.lua",
}

local passed, failed = 0, 0
for _, path in ipairs(suites) do
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write("LOAD ERROR " .. path .. ": " .. tostring(err) .. "\n")
        failed = failed + 1
    else
        local ok, runErr = pcall(chunk)
        if ok then
            passed = passed + 1
        else
            io.stderr:write("FAIL " .. path .. ": " .. tostring(runErr) .. "\n")
            failed = failed + 1
        end
    end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
