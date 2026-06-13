-- #EnhancedDump.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedDump", M)

local dumpText        = ""
local dumpFrame       = nil
local dumpEditBox     = nil
local dumpScrollFrame = nil

local function GetDumpFrame()
    if dumpFrame then return dumpFrame end

    dumpFrame = CreateFrame("Frame", "EnhancedProbeDumpFrame", UIParent, "BackdropTemplate")
    dumpFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
    dumpFrame:SetPoint("BOTTOMLEFT", UIParent, "TOPRIGHT", -620, -520)
    dumpFrame:SetFrameStrata("DIALOG")
    dumpFrame:SetMovable(true)
    dumpFrame:SetClampedToScreen(true)
    dumpFrame:EnableMouse(true)
    dumpFrame:RegisterForDrag("LeftButton")
    dumpFrame:SetScript("OnDragStart", dumpFrame.StartMoving)
    dumpFrame:SetScript("OnDragStop",  dumpFrame.StopMovingOrSizing)
    dumpFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dumpFrame:SetBackdropColor(0, 0, 0, 0.88)
    dumpFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    dumpFrame:Hide()

    local title = dumpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("EnhancedProbe Dump")

    local closeBtn = CreateFrame("Button", nil, dumpFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() dumpFrame:Hide() end)

    local hint = dumpFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -8, -8)
    hint:SetText("Ctrl+C to copy")

    dumpScrollFrame = CreateFrame("ScrollFrame", nil, dumpFrame, "UIPanelScrollFrameTemplate")
    dumpScrollFrame:SetPoint("TOPLEFT",  8, -28)
    dumpScrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

    dumpEditBox = CreateFrame("EditBox", nil, dumpScrollFrame)
    dumpEditBox:SetMultiLine(true)
    dumpEditBox:SetFontObject(GameFontHighlightSmall)
    dumpEditBox:SetWidth(460)
    dumpEditBox:SetAutoFocus(false)
    dumpEditBox:EnableMouse(true)
    dumpEditBox:SetScript("OnEscapePressed", function() dumpFrame:Hide() end)
    dumpEditBox:SetScript("OnMouseDown", function() dumpEditBox:SetFocus() end)
    dumpScrollFrame:SetScrollChild(dumpEditBox)

    dumpFrame:SetScript("OnShow", function()
        local w = dumpScrollFrame:GetWidth()
        if w > 0 then dumpEditBox:SetWidth(w) end
    end)

    return dumpFrame
end

function ns.DumpWrite(msg)
    if issecretvalue and issecretvalue(dumpText) then dumpText = "" end
    if dumpText ~= "" then dumpText = dumpText .. "\n" end
    dumpText = dumpText .. msg
    local df = GetDumpFrame()
    dumpEditBox:SetText(dumpText)
    local numLines = 1
    for _ in dumpText:gmatch("\n") do numLines = numLines + 1 end
    local h = numLines * 14 + 8
    dumpEditBox:SetHeight(math.max(h, dumpScrollFrame:GetHeight()))
    df:Show()
end

function ns.DumpClear()
    dumpText = ""
    if dumpEditBox then
        dumpEditBox:SetText("")
        dumpEditBox:SetHeight(dumpScrollFrame and dumpScrollFrame:GetHeight() or 400)
    end
end
