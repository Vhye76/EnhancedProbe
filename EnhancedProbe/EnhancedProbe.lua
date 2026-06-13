-- #EnhancedProbe.lua

local ADDON_NAME, ns = ...

ns.modules       = {}
ns.probes        = {}
ns.EventHandlers = {}

local eventFrame = CreateFrame("Frame", "EnhancedProbe_EventFrame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local list = ns.EventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end)

local runnerFrame = CreateFrame("Frame", "EnhancedProbe_RunnerFrame")
runnerFrame:Hide()

function ns.RegisterEvent(event, handler)
    if not ns.EventHandlers[event] then
        ns.EventHandlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    ns.EventHandlers[event][#ns.EventHandlers[event] + 1] = handler
end

function ns.RegisterModule(name, module)
    ns.modules[name] = module
end

function ns.RegisterProbe(name, fn)
    ns.probes[#ns.probes + 1] = { name = name, fn = fn }
end

local SLICE_MS     = 10
local CHECK_EVERY  = 1024
local PROBE_BUDGET = 30

local sliceStart = 0
local sinceCheck = 0

function ns.MaybeYield()
    sinceCheck = sinceCheck + 1
    if sinceCheck < CHECK_EVERY then return end
    sinceCheck = 0
    if coroutine.running() and debugprofilestop() - sliceStart > SLICE_MS then
        coroutine.yield()
    end
end

function ns.ClassifyValue(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    return type(v)
end

function ns.SerializeTree(value, maxDepth)
    local seen = {}
    local function copy(v, depth)
        ns.MaybeYield()
        if issecretvalue and issecretvalue(v) then return "<secret>" end
        local t = type(v)
        if t == "string" or t == "number" or t == "boolean" then return v end
        if t ~= "table" then return "<" .. t .. ">" end
        if seen[v] then return "<ref>" end
        if depth >= maxDepth then return "<maxdepth>" end
        seen[v] = true
        local result = {}
        for k, kv in pairs(v) do
            if not (issecretvalue and issecretvalue(k)) then
                local kt = type(k)
                local key = (kt == "string" or kt == "number") and k or tostring(k)
                result[key] = copy(kv, depth + 1)
            end
        end
        return result
    end
    return copy(value, 0)
end

local CHAT_PREFIX = "|cff44b544[Enhanced|r|cffe0B84fProbe|r|cff44b544]|r "

function ns.Print(msg)
    print(CHAT_PREFIX .. msg)
end

function ns.PrintError(msg)
    print(CHAT_PREFIX .. "|cffFF4444" .. msg .. "|r")
end

local function CaptureMeta()
    local clientVersion, clientBuild, clientDate, clientToc = GetBuildInfo()
    return {
        clientVersion = clientVersion,
        clientBuild   = clientBuild,
        clientDate    = clientDate,
        clientToc     = clientToc,
        capturedAt    = date("%Y-%m-%d %H:%M:%S"),
        addonVersion  = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"),
    }
end

function ns.RunBattery(filter)
    if ns.running then
        ns.PrintError("A capture is already running.")
        return
    end

    local toRun = {}
    for i = 1, #ns.probes do
        local probe = ns.probes[i]
        if not filter or probe.name == filter then
            toRun[#toRun + 1] = probe
        end
    end

    if #toRun == 0 then
        ns.PrintError(string.format("No probe named '%s'. '/eprobe list' shows the battery.", tostring(filter)))
        return
    end

    EnhancedProbeDB = EnhancedProbeDB or {}
    EnhancedProbeDB.captures = EnhancedProbeDB.captures or {}

    local capture = { meta = CaptureMeta(), results = {}, errors = {} }
    local total = #toRun
    local ran, failed = 0, 0
    local index, co, out, probeStart = 1, nil, nil, 0

    ns.running = true
    ns.Print(string.format("Running %d probe%s...", total, total == 1 and "" or "s"))

    runnerFrame:SetScript("OnUpdate", function()
        sliceStart = debugprofilestop()
        while index <= total do
            local probe = toRun[index]
            if not co then
                if debugprofilestop() - sliceStart > SLICE_MS then return end
                out = {}
                co = coroutine.create(probe.fn)
                probeStart = GetTime()
            end
            local ok, err = coroutine.resume(co, out)
            if coroutine.status(co) == "dead" then
                ran = ran + 1
                if ok then
                    capture.results[probe.name] = out
                else
                    failed = failed + 1
                    capture.errors[probe.name] = tostring(err)
                end
                ns.Print(string.format("[%d/%d] %s%s", index, total, probe.name, ok and "" or " (error)"))
                co, out = nil, nil
                index = index + 1
            elseif GetTime() - probeStart > PROBE_BUDGET then
                ran = ran + 1
                failed = failed + 1
                capture.errors[probe.name] = string.format("timed out after %ds", PROBE_BUDGET)
                ns.Print(string.format("[%d/%d] %s (timeout)", index, total, probe.name))
                co, out = nil, nil
                index = index + 1
            else
                return
            end
        end

        runnerFrame:SetScript("OnUpdate", nil)
        runnerFrame:Hide()
        ns.running = nil
        EnhancedProbeDB.captures = { capture }
        ns.Print(string.format("Capture complete: %d probes, %d errors. '/reload' flushes SavedVariables to disk.",
            ran, failed))
    end)
    runnerFrame:Show()
end

local function ShowLatest()
    if ns.running then
        ns.PrintError("A capture is in progress - wait for it to finish.")
        return
    end
    local caps = EnhancedProbeDB and EnhancedProbeDB.captures
    local cap = caps and caps[#caps]
    if not cap then
        ns.PrintError("No captures stored.")
        return
    end
    ns.DumpClear()
    ns.DumpWrite(string.format("Capture  client %s build %s  at %s",
        tostring(cap.meta.clientVersion), tostring(cap.meta.clientBuild), tostring(cap.meta.capturedAt)))
    for name, result in pairs(cap.results) do
        local n = 0
        for _ in pairs(result) do n = n + 1 end
        ns.DumpWrite(string.format("  %s: %d top-level entries", name, n))
    end
    for name, err in pairs(cap.errors) do
        ns.DumpWrite(string.format("  %s: ERROR %s", name, err))
    end
end

local function ShowUsage()
    ns.Print("Commands:")
    ns.Print("  /eprobe          run the full battery")
    ns.Print("  /eprobe <name>   run a single probe")
    ns.Print("  /eprobe show     show the latest capture in a copyable window")
    ns.Print("  /eprobe list     list commands and registered probes")
    ns.Print("  /eprobe wipe     clear all stored captures")
    ns.Print("Probes:")
    for i = 1, #ns.probes do
        ns.Print("  " .. ns.probes[i].name)
    end
end

SLASH_ENHANCEDPROBE1 = "/eprobe"

SlashCmdList.ENHANCEDPROBE = function(msg)
    local cmd = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "" then
        ns.RunBattery()
    elseif cmd == "list" or cmd == "help" then
        ShowUsage()
    elseif cmd == "show" then
        ShowLatest()
    elseif cmd == "wipe" then
        EnhancedProbeDB = { captures = {} }
        ns.Print("All captures wiped.")
    else
        ns.RunBattery(cmd)
    end
end

ns.RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    local v = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
    ns.Print(string.format("v%s loaded. '/eprobe' runs the full battery.", v))
end)
