#!/usr/bin/env luajit

local function loadSV(path)
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    local env = {}
    setfenv(chunk, env)
    local ok, ferr = pcall(chunk)
    if not ok then return nil, ferr end
    return env.EnhancedProbeDB
end

local function latest(db)
    local caps = db and db.captures
    return caps and caps[#caps] or nil
end

local lines = {}
local function emit(s) lines[#lines + 1] = s or "" end

local function withSection(title, fn)
    local start = #lines
    fn()
    if #lines > start then
        table.insert(lines, start + 1, "== " .. title .. " ==")
        table.insert(lines, start + 1, "")
    end
end

local function sortedKeys(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    return ks
end

local function diffKeys(old, new)
    old, new = old or {}, new or {}
    local added, removed, common = {}, {}, {}
    for _, k in ipairs(sortedKeys(new)) do
        if old[k] == nil then added[#added + 1] = k else common[#common + 1] = k end
    end
    for _, k in ipairs(sortedKeys(old)) do
        if new[k] == nil then removed[#removed + 1] = k end
    end
    return added, removed, common
end

local function reportScalarMap(prefix, old, new)
    local added, removed, common = diffKeys(old, new)
    for _, k in ipairs(removed) do emit(("  - %s%s"):format(prefix, k)) end
    for _, k in ipairs(added)   do emit(("  + %s%s  (%s)"):format(prefix, k, tostring(new[k]))) end
    for _, k in ipairs(common) do
        if old[k] ~= new[k] then
            emit(("  ~ %s%s  %s -> %s"):format(prefix, k, tostring(old[k]), tostring(new[k])))
        end
    end
end

-- #SECRETS

local function secretness(f)
    local s, plain = f.secret or 0, f.plain or 0
    if s > 0 and plain > 0 then return "mixed" end
    if s > 0 then return "secret" end
    return "plain"
end

local function opStatus(o)
    local ok, err = o.ok or 0, o.err or 0
    if ok > 0 and err > 0 then return "mixed" end
    if err > 0 then return "err" end
    if ok > 0 then return "ok" end
    return "none"
end

local function diffOps(field, old, new, p)
    local added, removed, common = diffKeys(old, new)
    for _, op in ipairs(removed) do p(("  %s op -%s"):format(field, op)) end
    for _, op in ipairs(added)   do p(("  %s op +%s (%s)"):format(field, op, opStatus(new[op]))) end
    for _, op in ipairs(common) do
        local so, sn = opStatus(old[op]), opStatus(new[op])
        if so ~= sn then p(("  %s op %s  %s -> %s"):format(field, op, so, sn)) end
    end
end

local function diffSecretContext(label, oc, nc)
    local of, nf = oc.fields or {}, nc.fields or {}
    local added, removed, common = diffKeys(of, nf)
    local function p(s) emit(("  [%s] %s"):format(label, s)) end
    for _, k in ipairs(removed) do p("- field " .. k) end
    for _, k in ipairs(added)   do p(("+ field %s (%s)"):format(k, secretness(nf[k]))) end
    for _, k in ipairs(common) do
        local fo, fn = of[k], nf[k]
        local so, sn = secretness(fo), secretness(fn)
        if so ~= sn then p(("~ field %s  %s -> %s"):format(k, so, sn)) end
        diffOps(k, fo.ops or {}, fn.ops or {}, p)
    end
end

local function diffSecrets(o, n)
    o, n = o or {}, n or {}
    withSection("SECRETS", function()
        local octx, nctx = o.contexts or {}, n.contexts or {}
        local added, removed, common = diffKeys(octx, nctx)
        for _, l in ipairs(removed) do emit("  - context " .. l) end
        for _, l in ipairs(added)   do emit("  + context " .. l) end
        for _, l in ipairs(common) do diffSecretContext(l, octx[l], nctx[l]) end
    end)
end

-- #CENSUS

local function diffCensus(o, n)
    o, n = o or {}, n or {}
    withSection("CENSUS: globals", function()
        reportScalarMap("", o.globals or {}, n.globals or {})
    end)
    withSection("CENSUS: namespaces", function()
        local added, removed, common = diffKeys(o.namespaces, n.namespaces)
        for _, ns in ipairs(removed) do emit("  - " .. ns) end
        for _, ns in ipairs(added)   do emit("  + " .. ns) end
        for _, ns in ipairs(common) do reportScalarMap(ns .. ".", o.namespaces[ns], n.namespaces[ns]) end
    end)
    withSection("CENSUS: enums", function()
        local added, removed, common = diffKeys(o.enums, n.enums)
        for _, e in ipairs(removed) do emit("  - " .. e) end
        for _, e in ipairs(added)   do emit("  + " .. e) end
        for _, e in ipairs(common) do reportScalarMap(e .. ".", o.enums[e], n.enums[e]) end
    end)
end

-- #FRAMES

local function diffFrames(o, n)
    o, n = o or {}, n or {}
    withSection("FRAMES: targets", function()
        local ot, nt = o.targets or {}, n.targets or {}
        local added, removed, common = diffKeys(ot, nt)
        for _, k in ipairs(removed) do emit("  - target " .. k) end
        for _, k in ipairs(added)   do emit(("  + target %s (present=%s)"):format(k, tostring(nt[k].present))) end
        for _, k in ipairs(common) do
            local to, tn = ot[k], nt[k]
            if to.present ~= tn.present then
                emit(("  ~ target %s present %s -> %s"):format(k, tostring(to.present), tostring(tn.present)))
            end
            if to.objectType ~= tn.objectType then
                emit(("  ~ target %s objectType %s -> %s"):format(k, tostring(to.objectType), tostring(tn.objectType)))
            end
            reportScalarMap(("    %s.keys."):format(k), to.keys or {}, tn.keys or {})
        end
    end)
    withSection("FRAMES: widget APIs", function()
        local ow, nw = o.widgetApis or {}, n.widgetApis or {}
        local added, removed, common = diffKeys(ow, nw)
        for _, k in ipairs(removed) do emit("  - widgetApi " .. k) end
        for _, k in ipairs(added)   do emit("  + widgetApi " .. k) end
        for _, k in ipairs(common) do reportScalarMap(("    %s."):format(k), ow[k], nw[k]) end
    end)
end

-- #DOCS

local function asKeyed(t)
    local n = #t
    if n == 0 then return nil end
    local keyed = {}
    for i = 1, n do
        local v = t[i]
        if type(v) ~= "table" or v.Name == nil then return nil end
        keyed[tostring(v.Name)] = v
    end
    return keyed
end

local deepDiff
deepDiff = function(path, o, n)
    if o == "<ref>" or n == "<ref>" then return end
    if type(o) ~= "table" or type(n) ~= "table" then
        if o ~= n then emit(("  ~ %s  %s -> %s"):format(path, tostring(o), tostring(n))) end
        return
    end
    local oo, nn = asKeyed(o) or o, asKeyed(n) or n
    local added, removed, common = diffKeys(oo, nn)
    for _, k in ipairs(removed) do emit(("  - %s.%s"):format(path, k)) end
    for _, k in ipairs(added)   do emit(("  + %s.%s"):format(path, k)) end
    for _, k in ipairs(common) do deepDiff(("%s.%s"):format(path, k), oo[k], nn[k]) end
end

local function diffDocs(o, n)
    o, n = o or {}, n or {}
    withSection("DOCS: availability", function()
        if tostring(o.present) ~= tostring(n.present) then
            emit(("  ~ present %s -> %s"):format(tostring(o.present), tostring(n.present)))
        end
        deepDiff("loadAttempts", o.loadAttempts or {}, n.loadAttempts or {})
    end)
    withSection("DOCS: tree", function()
        deepDiff("tree", o.tree or {}, n.tree or {})
    end)
end

-- #MAIN

local baseline, ptr = arg[1], arg[2]
if not baseline or not ptr then
    io.stderr:write("usage: luajit eprobe-diff.lua <baseline-sv.lua> <ptr-sv.lua>\n")
    os.exit(1)
end

local odb, oerr = loadSV(baseline)
if not odb then io.stderr:write("cannot load baseline: " .. tostring(oerr) .. "\n"); os.exit(1) end
local ndb, nerr = loadSV(ptr)
if not ndb then io.stderr:write("cannot load ptr: " .. tostring(nerr) .. "\n"); os.exit(1) end

local oc, nc = latest(odb), latest(ndb)
if not oc then io.stderr:write("baseline has no captures\n"); os.exit(1) end
if not nc then io.stderr:write("ptr has no captures\n"); os.exit(1) end

local function metaLine(tag, cap)
    local m = cap.meta or {}
    return ("  %-9s %s  build %s  at %s"):format(tag, tostring(m.clientVersion), tostring(m.clientBuild), tostring(m.capturedAt))
end

emit("EnhancedProbe API diff")
emit(metaLine("baseline", oc))
emit(metaLine("ptr", nc))

withSection("CAPTURE ERRORS (incomplete probes)", function()
    for _, pair in ipairs({ { "baseline", oc }, { "ptr", nc } }) do
        local tag, cap = pair[1], pair[2]
        for _, k in ipairs(sortedKeys(cap.errors or {})) do
            emit(("  [%s] %s: %s"):format(tag, k, tostring(cap.errors[k])))
        end
    end
end)

local ores, nres = oc.results or {}, nc.results or {}
diffSecrets(ores.secrets, nres.secrets)
diffCensus(ores.census, nres.census)
diffFrames(ores.frames, nres.frames)
diffDocs(ores.docs, nres.docs)

if #lines == 3 then emit(""); emit("No differences found.") end

io.write(table.concat(lines, "\n"), "\n")
