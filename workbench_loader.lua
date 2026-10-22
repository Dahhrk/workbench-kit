-- Workbench kit loader: the standalone install option for a server that does not run the Obsidian
-- gamemode or framework. Drop this file in garrysmod/lua/autorun/ and set the kit url once - convar
-- workbench_kit_url, data/workbench/kit_url.txt, or the KIT_URL constant below. First boot
-- fetches the kit json made by workbench_exportkit, writes the modules to data/workbench/runtime/,
-- and runs them for this realm. Every boot after runs from disk - the fetch is one-time only. When the real
-- gamemode's own workbench is loaded this loader stands down and does nothing.
local KIT_URL = "https://raw.githubusercontent.com/Dahhrk/workbench-kit/main/workbench_kit.json"
local RUNTIME = "workbench/runtime"
local ACCENT = Color(255, 46, 46)
local DIM = Color(140, 140, 140)
local BAD = Color(255, 96, 96)
local OK = Color(130, 220, 130)
local t0 = SysTime()

local function log(stage, text, col)
    MsgC(ACCENT, "[WB]  ", DIM, string.format("%-10s", tostring(stage)), col or color_white, tostring(text) .. "\n")
end

-- Pre-workbench loader chip: same role as WB.Loader() but standalone, so it can run before any kit module.
-- On a re-pull the old WB table is still alive, so the chip keeps showing your alias and accent through
-- the handoff to the real loader instead of flashing back to a red Workbench.
local function whoAmI()
    local me = istable(GM) and GM.Workbench or (istable(GAMEMODE) and GAMEMODE.Workbench)
    local ident = istable(me) and me.myIdentity
    if (not istable(ident)) then
        local stored = util.JSONToTable(file.Read("workbench/identity.json", "DATA") or "")
        ident = istable(stored) and stored or nil
    end
    local alias = (istable(ident) and ident.alias) or "Workbench"
    local acc = (istable(ident) and istable(ident.accent)) and ident.accent or ACCENT
    return "[" .. tostring(alias) .. "]", acc
end
-- Orb icon identical to cl_board's drawOrbIcon: accent glow, specular core, orbiting arc. The workbench
-- loader adopts this panel wholesale, so the icon must not change at the handoff.
local orbMat
local pth
local orbSeg = {}
for i = 0, 15 do
    local t = i / 16 * math.pi * 2
    orbSeg[i + 1] = {x = math.cos(t), y = math.sin(t)}
end
local function orbDisc(cx, cy, r, col)
    local p = {}
    for i = 1, #orbSeg do p[i] = {x = cx + orbSeg[i].x * r, y = cy + orbSeg[i].y * r} end
    draw.NoTexture()
    surface.SetDrawColor(col.r, col.g, col.b, col.a)
    surface.DrawPoly(p)
end
local function orbArc(cx, cy, rO, rI, a0, sweep, col)
    local p, steps = {}, 14
    for i = 0, steps do
        local t = math.rad(a0 + sweep * i / steps)
        p[#p + 1] = {x = cx + math.cos(t) * rO, y = cy + math.sin(t) * rO}
    end
    for i = steps, 0, -1 do
        local t = math.rad(a0 + sweep * i / steps)
        p[#p + 1] = {x = cx + math.cos(t) * rI, y = cy + math.sin(t) * rI}
    end
    draw.NoTexture()
    surface.SetDrawColor(col.r, col.g, col.b, col.a)
    surface.DrawPoly(p)
end
local function drawOrbIcon(cx, cy, acc, a)
    orbDisc(cx, cy, 9.5, Color(acc.r, acc.g, acc.b, a * 0.10))
    orbDisc(cx, cy, 7.8, Color(acc.r, acc.g, acc.b, a * 0.18))
    orbArc(cx, cy, 8.7, 7.3, CurTime() * 220 % 360, 130, Color(acc.r, acc.g, acc.b, a))
    if (not orbMat or orbMat:IsError()) then
        orbMat = Material("workbench/orbs64.png", "smooth")
        -- Standalone has no materials tree; the pack static lands in the Mortis-shaped cache instead.
        if (orbMat:IsError() and pth) then
            local rel = "workbench/cache/static/" .. pth("Workbench/icon/orbs64.png")
            if (file.Exists(rel, "DATA")) then orbMat = Material("../data/" .. rel, "smooth") end
        end
    end
    if (not orbMat:IsError()) then
        surface.SetDrawColor(255, 255, 255, a)
        surface.SetMaterial(orbMat)
        surface.DrawTexturedRectRotated(cx, cy, 12, 12, 0)
    else
        orbDisc(cx, cy, 5.2, Color(15, 15, 19, a))
        orbDisc(cx, cy, 4.0, Color(acc.r, acc.g, acc.b, a))
        orbDisc(cx - 1.2, cy - 1.4, 1.1, Color(255, 255, 255, a * 0.85))
    end
end
local ROUTE_NODES = {"pull", "install", "exec", "sync", "done"}
local ROUTE_EDGES = {0, 0.2, 0.6, 0.8, 1}
local chip
if (CLIENT) then
    hook.Add("PostRender", "WB.BootSpawn", function()
        if (IsValid(LocalPlayer()) and LocalPlayer():Alive()) then _G.WB_Spawned = true hook.Remove("PostRender", "WB.BootSpawn") end
    end)
end
local function ensureChip()
    if (not CLIENT) then return nil end
    if (IsValid(chip)) then return chip end
    surface.CreateFont("WBBoot.Loader", {font = "Arial", size = 13, weight = 500, extended = true, antialias = true})
    surface.CreateFont("WBBoot.Brand", {font = "Arial", size = 12, weight = 800, extended = true, antialias = true})
    surface.CreateFont("WBBoot.Tiny", {font = "Arial", size = 9, weight = 600, extended = true, antialias = true})
    if (IsValid(_G.WB_BootChip)) then _G.WB_BootChip:Remove() end
    chip = vgui.Create("Panel")
    chip:SetSize(260, 34)
    chip.Text = "awaiting"
    chip.Progress = 0
    chip.Pulse = false
    chip.Alpha = 0
    chip.FadeOut = false
    function chip:Think()
        if (not _G.WB_Spawned or gui.IsGameUIVisible()) then return end
        local w, h = self:GetSize()
        local x, y = math.floor(ScrW() / 2 - w / 2), ScrH() - h - 28
        if (x ~= self:GetX() or y ~= self:GetY()) then self:SetPos(x, y) end
        local goal = self.FadeOut and 0 or 1
        if (self.Alpha ~= goal) then
            self.Alpha = math.Clamp(self.Alpha + (self.FadeOut and -1 or 1) * FrameTime() * 5, 0, 1)
            if (self.FadeOut and self.Alpha <= 0) then self:Remove() end
        end
    end
    function chip:Paint(w, h)
        if (not _G.WB_Spawned or gui.IsGameUIVisible()) then return end
        local a = (self.Alpha or 0) * 255
        if (a <= 0) then return end
        draw.RoundedBox(10, 0, 0, w, h, Color(255, 255, 255, a * 0.10))
        draw.RoundedBox(10, 1, 1, w - 2, h - 2, Color(13, 13, 16, a * 0.92))
        local brand, acc = whoAmI()
        drawOrbIcon(16, h / 2 - 2, acc, a)
        draw.SimpleText(brand, "WBBoot.Brand", 30, h / 2 - 2, Color(acc.r, acc.g, acc.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont("WBBoot.Brand")
        local bw = surface.GetTextSize(brand)
        draw.SimpleText(self.Text, "WBBoot.Loader", 34 + bw, h / 2 - 2, Color(235, 235, 235, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        self.Shown = (self.Shown or 0) + ((self.Progress or 0) - (self.Shown or 0)) * math.min(FrameTime() * 8, 0.22)
        local prog = math.Clamp(self.Progress or 0, 0, 1)
        local frac = math.Clamp(self.Shown or 0, 0, 1)
        local node = #ROUTE_NODES
        for n = 1, #ROUTE_EDGES do
            if (prog < ROUTE_EDGES[n]) then node = math.max(1, n - 1) break end
        end
        local seg = (w - 16 - (#ROUTE_NODES - 1) * 4) / #ROUTE_NODES
        for n = 1, #ROUTE_NODES do
            local sx = 8 + (n - 1) * (seg + 4)
            surface.SetDrawColor(255, 255, 255, a * 0.08)
            surface.DrawRect(sx, h - 5, seg, 2)
            local f = 0
            if (n < node) then f = 1
            elseif (n == node) then
                f = (n == #ROUTE_NODES) and 1 or math.Clamp((frac - ROUTE_EDGES[n]) / (ROUTE_EDGES[n + 1] - ROUTE_EDGES[n]), 0, 1)
            end
            if (self.Pulse and n == node) then f = (math.sin(CurTime() * 4) + 1) / 2 end
            if (f > 0) then
                surface.SetDrawColor(acc.r, acc.g, acc.b, a)
                surface.DrawRect(sx, h - 5, seg * f, 2)
            end
            draw.SimpleText(ROUTE_NODES[n], "WBBoot.Tiny", sx + seg / 2, h - 10, n <= node and Color(acc.r, acc.g, acc.b, a * 0.9) or Color(140, 140, 140, a * 0.55), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(node .. "/" .. #ROUTE_NODES, "WBBoot.Brand", w - 8, h / 2 - 2, Color(140, 140, 140, a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    function chip:Say(text, progress)
        self.Text = tostring(text)
        if (isnumber(progress) and progress ~= -1) then
            if (self.Pulse) then self.Shown = (math.sin(CurTime() * 4) + 1) / 2 end
            self.Progress = progress
            self.Pulse = false
        elseif (progress == -1) then
            if (not self.Pulse) then self.PulseStart = CurTime() end
            self.Pulse = true
        end
        surface.SetFont("WBBoot.Brand")
        local bw = surface.GetTextSize((whoAmI()))
        surface.SetFont("WBBoot.Loader")
        local tw = surface.GetTextSize(self.Text)
        self._peakW = math.max(self._peakW or 0, 300, 48 + bw + tw + 30)
        self:SetWide(self._peakW)
        self:SetPos(ScrW() / 2 - self:GetWide() / 2, ScrH() - self:GetTall() - 28)
        self:SetVisible(true)
        self.FadeOut = false
    end
    function chip:Done(text, hold)
        self:Say(text, 1)
        timer.Simple(tonumber(hold) or 2, function() if (IsValid(chip)) then chip.FadeOut = true end end)
    end
    function chip:Fail(text)
        self:Say(text, 0)
        timer.Simple(4, function() if (IsValid(chip)) then chip.FadeOut = true end end)
    end
    _G.WB_BootChip = chip
    concommand.Add("workbench_hideui", function()
        if (IsValid(chip)) then chip:Remove() end
        local w = istable(GM) and GM.Workbench
        if (istable(w) and w.LoaderHide) then w.LoaderHide() end
        if (istable(w) and w.Loader) then local p = w.Loader() if IsValid(p) then p:SetVisible(false) end end
    end)
    return chip
end

local function stage(text, progress)
    local c = ensureChip()
    if (IsValid(c)) then c:Say(text, progress) end
end

local function bundled()
    if (istable(GM) and istable(GM.Workbench) and GM.Workbench.DATA ~= nil) then return true end
    if (istable(GAMEMODE) and istable(GAMEMODE.Workbench) and GAMEMODE.Workbench.DATA ~= nil) then return true end
    if (not file.Exists("obsidian/gamemode/modules/base/workbench/_loader.lua", "LUA")) then return false end
    -- A mounted addon's workbench only boots through darkrp_modules - under sandbox the file is inert, so
    -- presence alone cannot stand this loader down. DarkRP's global lands before the module sweep ends.
    if (istable(DarkRP)) then return true end
    return engine.ActiveGamemode and engine.ActiveGamemode() == "darkrp" or false
end

local function kitURL()
    local cvar = GetConVar and GetConVar("workbench_kit_url")
    local url = cvar and cvar:GetString() or ""
    if (url == "") then url = file.Read("workbench/kit_url.txt", "DATA") or "" end
    url = string.gsub(url, "%s+$", "")
    if (url == "") then url = KIT_URL end
    return url
end

local function realmOk(m)
    return m.realm == "shared" or (m.realm == "server" and SERVER) or (m.realm == "client" and CLIENT)
end

local function execModule(m, ran, total)
    local code = file.Read(RUNTIME .. "/" .. tostring(m.file or ""), "DATA")
    if (not code) then log("module", m.name .. " - missing " .. tostring(m.file), BAD) return false end
    local fn = CompileString(code, "workbench_kit/" .. m.name .. ".lua", false)
    if (not isfunction(fn)) then log("module", m.name .. " - " .. tostring(fn), BAD) return false end
    local ok, err = pcall(fn)
    if (not ok) then log("module", m.name .. " - " .. tostring(err), BAD) return false end
    if (IsValid(chip) and total) then chip:Say("executing", 0.6 + 0.2 * (ran / math.max(total, 1))) end
    return true
end

-- Install + module exec used to run in one frame - on a real kit that is a visible hitch, so the pull path
-- runs inside a coroutine and the loops drop a frame between units. Sync callers fall through untouched.
local function maybeYield()
    if (coroutine.running()) then coroutine.yield() end
end
local function stepThrough(fn)
    local co = coroutine.create(fn)
    local function pump()
        timer.Simple(0, function()
            local ok, err = coroutine.resume(co)
            if (not ok) then
                log("boot", tostring(err), BAD)
                stage("boot error - see console", 0)
                return
            end
            if (coroutine.status(co) ~= "dead") then pump() end
        end)
    end
    pump()
end

local function runManifest()
    if (_G.WB_KitRan or bundled()) then
        if (IsValid(chip)) then
            if (_G.WB_KitRan) then
                chip:Say("updated - map reload to apply", 1)
                timer.Simple(3, function() if (IsValid(chip)) then chip.FadeOut = true end end)
            else
                chip.FadeOut = true
            end
        end
        return true
    end
    local raw = file.Read(RUNTIME .. "/manifest.json", "DATA")
    local manifest = raw and util.JSONToTable(raw) or nil
    if (not istable(manifest) or not istable(manifest.modules)) then return false end
    if (istable(GAMEMODE)) then GAMEMODE.Workbench = GAMEMODE.Workbench or {} end
    if (istable(GM)) then GM.Workbench = GM.Workbench or {} end
    _G.WB_KitRan = true
    stage("executing", 0.6)
    local ran, total = 0, 0
    for _, m in ipairs(manifest.modules) do if (realmOk(m)) then total = total + 1 end end
    log("exec", tostring(manifest.name) .. " v" .. tostring(manifest.version) .. " (" .. total .. " modules)")
    for _, m in ipairs(manifest.modules) do
        if (realmOk(m) and execModule(m, ran, total)) then ran = ran + 1 end
        maybeYield()
    end
    local elapsed = string.format("%.2fs", SysTime() - t0)
    log("ready", ran .. "/" .. total .. " modules in " .. elapsed, ran == total and OK or BAD)
    -- Package sync still runs after exec (~Complete~ is the real end): hold the chip on a pulse and let the
    -- module loader take over - it fades this chip on its first stage update.
    if (IsValid(chip)) then
        if (ran == total) then chip:Say("syncing", -1)
        else chip:Fail(ran .. "/" .. total .. " modules - see console") end
    end
    if (CLIENT and ran > 0) then log("open", "type >> in chat", DIM) end
    return ran > 0
end

-- Mortis's storage mediums verbatim: lua entries land compressed under cache/lua, statics raw under
-- cache/static, both addressed by their PTH'd package virtual so a kit-installed file reads as an
-- already-cached entry when the checksum sweep runs - no second pull for what the kit just shipped.
pth = function(path)
    local f = path:match("^.+/(.+)$") or path
    local base, ext = f:match("^(.*)(%.[^./\\]+)$")
    local kept = ""
    if (base and ext and ext == ".lua") then
        path = path:sub(1, #path - #ext)
        kept = ext
        ext = ".dat"
    else
        ext = ext or ""
    end
    local segs = string.Explode("/", path)
    segs[#segs] = segs[#segs] .. kept
    for i = 1, #segs do segs[i] = util.CRC(segs[i]) end
    segs[#segs] = segs[#segs] .. ext
    return table.concat(segs, "/")
end
local function cachePath(rel)
    if (string.sub(rel, 1, 5) == "libs/") then
        return "workbench/cache/lua/" .. pth("Workbench/libraries/" .. string.sub(rel, 6)), "lua"
    end
    return "workbench/cache/static/" .. pth("Workbench/" .. rel), "static"
end
local function mkdirp(path)
    local acc = ""
    for part in string.gmatch(path, "[^/]+") do
        acc = acc == "" and part or acc .. "/" .. part
        file.CreateDir(acc)
        if (not file.Exists(acc, "DATA")) then log("install", "mkdir failed: " .. acc, BAD) return false end
    end
    return true
end
local function install(body)
    local kit = util.JSONToTable(body)
    if (not istable(kit) or not istable(kit.modules)) then
        log("fetch", "not a kit payload", BAD)
        if (IsValid(chip)) then chip:Fail("bad payload") end
        return
    end
    log("install", #kit.modules .. " modules")
    local fresh = not file.Exists(RUNTIME .. "/manifest.json", "DATA")
    if (not mkdirp(RUNTIME)) then if (IsValid(chip)) then chip:Fail("write blocked") end return end
    local manifest = {name = kit.name or "workbench", version = kit.version or os.time(), kit = tostring(kit.id or "0"), modules = {}}
    local wrote, total = 0, #kit.modules
    for i, m in ipairs(kit.modules) do
        local code = util.Base64Decode(tostring(m.code or ""))
        if (code and isstring(m.name) and isstring(m.realm)) then
            local slot = "m" .. i .. ".dat"
            file.Write(RUNTIME .. "/" .. slot, code)
            if (not file.Exists(RUNTIME .. "/" .. slot, "DATA")) then log("install", "write failed: " .. slot, BAD) goto skip end
            manifest.modules[#manifest.modules + 1] = {name = m.name, realm = m.realm, file = slot}
            wrote = wrote + 1
            if (IsValid(chip)) then chip:Say("installing " .. wrote .. "/" .. total, 0.2 + 0.4 * (wrote / total)) end
        end
        ::skip::
        maybeYield()
    end
    local page, shell = util.Base64Decode(tostring(kit.page or "")), util.Base64Decode(tostring(kit.shell or ""))
    if (page and shell) then
        file.CreateDir("workbench")
        file.Write("workbench/page.txt", page)
        file.Write("workbench/shell.txt", shell)
    end
    for rel, b64 in pairs(kit.files or {}) do
        maybeYield()
        local data = util.Base64Decode(tostring(b64))
        if (data) then
            local path, medium = cachePath(rel)
            mkdirp(path:match("^(.*)/"))
            file.Write(path, medium == "static" and data or util.Compress(data))
            if (not file.Exists(path, "DATA")) then log("install", "file write failed: " .. rel, BAD) end
        end
    end
    file.Write(RUNTIME .. "/manifest.json", util.TableToJSON(manifest))
    log("installed", wrote .. "/" .. total .. " modules", wrote == total and color_white or BAD)
    if (fresh) then runManifest() end
end

local function fetch()
    local url = kitURL()
    if (url == "") then log("fetch", "no kit url - set workbench_kit_url or data/workbench/kit_url.txt", BAD) return end
    stage("fetching", -1)
    log("fetch", "workbench_kit.json")
    log("source", url, DIM)
    http.Fetch(url, install, function(err)
        log("fetch", tostring(err), BAD)
        if (IsValid(chip)) then chip:Fail("fetch failed") end
    end)
end

-- Client pull: a planted loader asks the connected server for the kit and the server streams it back in
-- chunks - same shape as the reference bootstrap, except the server answers only while the player passes
-- WB.Access and logs the pull in the audit trail.
local KIT_NET = "Workbench.Kit"
local incoming

-- Self-clocked pull: each answered chunk triggers the next request, so at most one message is ever in
-- flight and the reliable channel cannot overflow no matter the rate limit.
local function pullChunk(i)
    net.Start(KIT_NET)
    net.WriteUInt(i, 16)
    net.SendToServer()
end

local function pull()
    incoming = nil
    pullChunk(0)
    stage("requesting kit", -1)
    log("pull", "requesting kit from server")
    timer.Simple(15, function()
        incoming = nil
        if (not runManifest()) then fetch() end
    end)
end

if (CLIENT) then
    net.Receive(KIT_NET, function()
        local idx, total = net.ReadUInt(16), net.ReadUInt(16)
        if (total == 0) then
            local why = net.ReadString()
            log("pull", "refused: " .. why, BAD)
            if (IsValid(chip)) then chip:Fail("refused - see console") end
            return
        end
        if (idx == 0) then
            incoming = {parts = {}, total = total}
            incoming.name, incoming.version = net.ReadString(), net.ReadDouble()
            if (IsValid(chip)) then chip:Say("receiving 0/" .. total, 0.05) end
            return pullChunk(1)
        end
        if (not incoming) then return end
        incoming.parts[idx] = net.ReadData(net.ReadUInt(16))
        if (IsValid(chip)) then chip:Say("receiving " .. idx .. "/" .. incoming.total, 0.05 + 0.15 * (idx / incoming.total)) end
        if (idx < incoming.total) then return pullChunk(idx + 1) end
        local body = util.Decompress(table.concat(incoming.parts))
        incoming = nil
        if (not body) then return log("pull", "kit arrived damaged", BAD) end
        stepThrough(function() install(body) runManifest() end)
    end)
end

local function go()
    if (runManifest()) then return end
    if (CLIENT) then pull() else fetch() end
end

local function boot()
    if (bundled()) then return end
    if (SERVER) then CreateConVar("workbench_kit_url", KIT_URL, FCVAR_ARCHIVE, "URL of the workbench kit json") end
    -- Sandbox can never host the gamemode-layer workbench, so there is nothing to wait for. Elsewhere a
    -- mounted framework can still be mid-load when this fires - give the live check a window to settle.
    if (engine.ActiveGamemode and engine.ActiveGamemode() == "sandbox") then return go() end
    local reps = 0
    timer.Create("WB.BundledWait", 0.5, 60, function()
        reps = reps + 1
        if (bundled()) then timer.Remove("WB.BundledWait") return end
        if (reps == 60) then go() end
    end)
end

timer.Simple(1, boot)

concommand.Add("workbench_kit_update", function(ply)
    if (IsValid(ply) and not ply:IsSuperAdmin()) then return end
    log("pull", "checking for kit update")
    if (CLIENT) then pull() else fetch() end
end)
