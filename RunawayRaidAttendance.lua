-- ============================================================================
-- Runaway Raid Attendance v2.0
-- Visual identity matching raid.runaway.com.br
-- Features: CSV export (Alto/Largo), Guild Invite by Rank, Assist by Rank
-- ============================================================================

local addonName, addon = ...

-- ============================================================================
-- SAVED VARIABLES
-- ============================================================================

RunawayRaidAttendanceDB = RunawayRaidAttendanceDB or {
    history = {},
    settings = {
        csvFormat = "alto",
        minimapAngle = 220,
    },
}

-- ============================================================================
-- PALETTE (matching raid.runaway.com.br)
-- ============================================================================

local P = {
    bg       = { 13/255, 13/255, 13/255, 0.95 },       -- #0d0d0d
    card     = { 26/255, 26/255, 26/255, 1 },           -- #1a1a1a
    border   = { 58/255, 58/255, 58/255, 1 },           -- #3a3a3a
    accent   = { 196/255, 32/255, 32/255, 1 },          -- #c42020
    accentL  = { 224/255, 53/255, 53/255, 1 },          -- #e03535
    accentD  = { 114/255, 14/255, 14/255, 1 },          -- #720e0e
    text     = { 240/255, 232/255, 232/255, 1 },        -- #f0e8e8
    dim      = { 122/255, 85/255, 85/255, 1 },          -- #7a5555
    dimLight = { 168/255, 128/255, 128/255, 1 },        -- #a88080
    green    = { 74/255, 222/255, 128/255, 1 },         -- #4ade80
    red      = { 248/255, 113/255, 113/255, 1 },        -- #f87171
    yellow   = { 250/255, 204/255, 21/255, 1 },         -- #facc15
}

-- ============================================================================
-- UTILIDADES
-- ============================================================================

local function GetDateISO()
    return date("%Y-%m-%d")
end

local function StripRealm(name)
    if not name then return "Unknown" end
    local dash = string.find(name, "-")
    if dash then return string.sub(name, 1, dash - 1) end
    return name
end

local function EscapeCSV(val)
    val = tostring(val or "")
    if string.find(val, '[,"\n]') then
        val = '"' .. string.gsub(val, '"', '""') .. '"'
    end
    return val
end

local function SetBackdropCustom(frame, bgColor, borderColor)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(unpack(bgColor or P.card))
    frame:SetBackdropBorderColor(unpack(borderColor or P.border))
end

-- Styled button factory
local function CreateStyledButton(parent, text, width, height, variant)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 130, height or 28)

    if not btn.SetBackdrop then
        Mixin(btn, BackdropTemplateMixin)
    end

    local isPrimary = (variant == "primary")
    local isDanger = (variant == "danger")
    local isSuccess = (variant == "success")

    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    local bgR, bgG, bgB, bgA
    local borderR, borderG, borderB
    local textR, textG, textB

    if isPrimary then
        bgR, bgG, bgB, bgA = P.accent[1], P.accent[2], P.accent[3], 0.9
        borderR, borderG, borderB = P.accentL[1], P.accentL[2], P.accentL[3]
        textR, textG, textB = 1, 1, 1
    elseif isDanger then
        bgR, bgG, bgB, bgA = P.red[1]*0.15, P.red[2]*0.15, P.red[3]*0.15, 0.9
        borderR, borderG, borderB = P.red[1]*0.4, P.red[2]*0.4, P.red[3]*0.4
        textR, textG, textB = P.red[1], P.red[2], P.red[3]
    elseif isSuccess then
        bgR, bgG, bgB, bgA = P.green[1]*0.15, P.green[2]*0.15, P.green[3]*0.15, 0.9
        borderR, borderG, borderB = P.green[1]*0.4, P.green[2]*0.4, P.green[3]*0.4
        textR, textG, textB = P.green[1], P.green[2], P.green[3]
    else
        bgR, bgG, bgB, bgA = P.card[1]*1.3, P.card[2]*1.3, P.card[3]*1.3, 0.9
        borderR, borderG, borderB = P.border[1], P.border[2], P.border[3]
        textR, textG, textB = P.text[1], P.text[2], P.text[3]
    end

    btn:SetBackdropColor(bgR, bgG, bgB, bgA)
    btn:SetBackdropBorderColor(borderR, borderG, borderB, 0.8)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("CENTER")
    btn.label:SetText(text)
    btn.label:SetTextColor(textR, textG, textB)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(bgR*1.3, bgG*1.3, bgB*1.3, 1)
        if isPrimary then
            self:SetBackdropBorderColor(P.accentL[1], P.accentL[2], P.accentL[3], 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(bgR, bgG, bgB, bgA)
        self:SetBackdropBorderColor(borderR, borderG, borderB, 0.8)
    end)

    return btn
end

-- ============================================================================
-- COLETA DE DADOS
-- ============================================================================

local function CollectRaidRoster()
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then
        return nil, "Voce nao esta em um grupo ou raid."
    end

    local isRaid = IsInRaid()
    local players = {}
    local dateStr = GetDateISO()

    if isRaid then
        for i = 1, numMembers do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name then
                table.insert(players, {
                    name = StripRealm(name),
                    present = (online ~= false),
                })
            end
        end
    else
        local playerName = UnitName("player")
        table.insert(players, { name = playerName, present = true })
        for i = 1, numMembers - 1 do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                table.insert(players, {
                    name = StripRealm(name),
                    present = UnitIsConnected(unit) ~= false,
                })
            end
        end
    end

    table.sort(players, function(a, b) return a.name < b.name end)

    return { date = dateStr, players = players, totalPresent = 0, totalAbsent = 0 }
end

-- ============================================================================
-- GERAR CSV
-- ============================================================================

local function GenerateCSVAlto(data)
    if not data or #data.players == 0 then return "" end
    local lines = { "date,player" }
    local present, absent = 0, 0
    for _, p in ipairs(data.players) do
        if p.present then
            table.insert(lines, data.date .. "," .. EscapeCSV(p.name))
            present = present + 1
        else
            absent = absent + 1
        end
    end
    data.totalPresent, data.totalAbsent = present, absent
    return table.concat(lines, "\n")
end

local function GenerateCSVLargo(data)
    if not data or #data.players == 0 then return "" end
    local names, values = {}, {}
    local present, absent = 0, 0
    for _, p in ipairs(data.players) do
        table.insert(names, EscapeCSV(p.name))
        if p.present then
            table.insert(values, "1")
            present = present + 1
        else
            table.insert(values, "0")
            absent = absent + 1
        end
    end
    data.totalPresent, data.totalAbsent = present, absent
    return "date," .. table.concat(names, ",") .. "\n" .. data.date .. "," .. table.concat(values, ",")
end

local function GenerateCSV(data)
    if RunawayRaidAttendanceDB.settings.csvFormat == "largo" then
        return GenerateCSVLargo(data)
    end
    return GenerateCSVAlto(data)
end

-- ============================================================================
-- GUILD FUNCTIONS: INVITE & ASSIST
-- Guild Rank 0 = GM, 1..N = custom ranks
-- Trial = Rank 6 → invite ranks 0-6 (incluindo Trial)
-- Assist = Ranks 2 e 3
-- Invite: avisa na guild 10s antes de convidar
-- ============================================================================

local function GetOnlineGuildMembers()
    local members = {}
    local numTotal = GetNumGuildMembers()
    for i = 1, numTotal do
        local name, _, rankIndex, level, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then
            table.insert(members, {
                name = name,
                displayName = StripRealm(name),
                rankIndex = rankIndex,
                level = level,
            })
        end
    end
    return members
end

local inviteTimerActive = false

local function DoInviteGuildMembers()
    local members = GetOnlineGuildMembers()
    local playerName = UnitName("player")
    local invited = 0

    for _, m in ipairs(members) do
        -- Rank 0-6 = inclui Trial (rank 6)
        if m.rankIndex <= 6 and StripRealm(m.name) ~= playerName then
            InviteUnit(m.name)
            invited = invited + 1
        end
    end

    inviteTimerActive = false
    return invited
end

local function InviteGuildByRank(statusCallback)
    if not IsInGuild() then
        print("|cffcc2020[Runaway]|r Voce nao esta em uma guild.")
        return
    end

    if inviteTimerActive then
        print("|cffcc2020[Runaway]|r Invites ja estao em andamento, aguarde...")
        return
    end

    inviteTimerActive = true

    -- Aviso no chat da guild
    SendChatMessage("Invites em 10s! Vem pra raid!", "GUILD")
    print("|cffcc2020[Runaway]|r Aviso enviado na guild. Invites em 10 segundos...")

    if statusCallback then
        statusCallback("|cfffacc15Invites em 10s...|r Aviso enviado no chat da guild.")
    end

    -- Timer de 10 segundos, depois faz os invites
    C_Timer.After(10, function()
        local count = DoInviteGuildMembers()
        print("|cffcc2020[Runaway]|r " .. count .. " convites enviados (Ranks 0-6, incluindo Trial).")
        if statusCallback then
            statusCallback(string.format("|cff4ade80%d convites enviados|r (Ranks 0-6, incluindo Trial).", count))
        end
    end)
end

local function PromoteAssists()
    if not IsInRaid() then
        print("|cffcc2020[Runaway]|r Voce precisa estar em uma raid para dar assist.")
        return 0
    end

    if not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
        print("|cffcc2020[Runaway]|r Voce precisa ser lider ou assistente.")
        return 0
    end

    -- Mapear guild members com rank
    local guildRanks = {}
    local numTotal = GetNumGuildMembers()
    for i = 1, numTotal do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name then
            guildRanks[StripRealm(name)] = rankIndex
        end
    end

    local promoted = 0
    local numMembers = GetNumGroupMembers()

    for i = 1, numMembers do
        local name, rank = GetRaidRosterInfo(i)
        if name then
            local displayName = StripRealm(name)
            local guildRank = guildRanks[displayName]
            -- Rank 2 ou 3 na guild → dar assist (se ainda nao tem)
            if guildRank and (guildRank == 2 or guildRank == 3) and rank == 0 then
                PromoteToAssistant("raid" .. i)
                promoted = promoted + 1
            end
        end
    end

    return promoted
end

-- ============================================================================
-- MAIN FRAME
-- ============================================================================

local MainFrame = CreateFrame("Frame", "RunawayAttendanceFrame", UIParent, "BackdropTemplate")
MainFrame:SetSize(740, 540)
MainFrame:SetPoint("CENTER")
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)
MainFrame:SetFrameStrata("DIALOG")
MainFrame:Hide()

SetBackdropCustom(MainFrame, { 13/255, 13/255, 13/255, 0.97 }, P.border)

-- Top accent line
local AccentLine = MainFrame:CreateTexture(nil, "OVERLAY")
AccentLine:SetHeight(2)
AccentLine:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 1, -1)
AccentLine:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -1, -1)
AccentLine:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 1)

-- Close button
local CloseBtn = CreateFrame("Button", nil, MainFrame)
CloseBtn:SetSize(24, 24)
CloseBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -8, -8)
CloseBtn.label = CloseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
CloseBtn.label:SetPoint("CENTER")
CloseBtn.label:SetText("x")
CloseBtn.label:SetTextColor(P.dim[1], P.dim[2], P.dim[3])
CloseBtn:SetScript("OnClick", function() MainFrame:Hide() end)
CloseBtn:SetScript("OnEnter", function(self) self.label:SetTextColor(P.red[1], P.red[2], P.red[3]) end)
CloseBtn:SetScript("OnLeave", function(self) self.label:SetTextColor(P.dim[1], P.dim[2], P.dim[3]) end)

-- ============================================================================
-- HEADER: Logo + Title
-- ============================================================================

local HeaderFrame = CreateFrame("Frame", nil, MainFrame)
HeaderFrame:SetHeight(50)
HeaderFrame:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 15, -10)
HeaderFrame:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -40, -10)

-- Logo texture (will use guild emblem or fallback icon)
local LogoTex = HeaderFrame:CreateTexture(nil, "ARTWORK")
LogoTex:SetSize(40, 40)
LogoTex:SetPoint("LEFT", HeaderFrame, "LEFT", 0, 0)
LogoTex:SetTexture("Interface\\Icons\\Ability_Mount_WhiteDireWolf")

-- Title
local TitleText = HeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
TitleText:SetPoint("LEFT", LogoTex, "RIGHT", 10, 6)
TitleText:SetText("|cffcc2020RUNAWAY|r")

-- Subtitle
local SubText = HeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
SubText:SetPoint("TOPLEFT", TitleText, "BOTTOMLEFT", 0, -2)
SubText:SetText("|cffa88080Raid Attendance Tracker|r")

-- ============================================================================
-- STATUS AREA
-- ============================================================================

local StatusText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
StatusText:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 15, -62)
StatusText:SetWidth(710)
StatusText:SetJustifyH("LEFT")
StatusText:SetText("|cffa88080Clique em Capturar Raid para gerar o CSV.|r")

local InfoText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
InfoText:SetPoint("TOPLEFT", StatusText, "BOTTOMLEFT", 0, -3)
InfoText:SetWidth(710)
InfoText:SetJustifyH("LEFT")
InfoText:SetTextColor(P.dim[1], P.dim[2], P.dim[3])

-- Format indicator
local FormatLabel = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
FormatLabel:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -15, -65)
FormatLabel:SetJustifyH("RIGHT")

local function UpdateFormatLabel()
    local fmt = RunawayRaidAttendanceDB.settings.csvFormat
    if fmt == "largo" then
        FormatLabel:SetText("|cffa88080Formato:|r |cffcc2020Largo|r")
    else
        FormatLabel:SetText("|cffa88080Formato:|r |cffcc2020Alto|r")
    end
end

-- ============================================================================
-- CSV TEXT AREA (dark editbox)
-- ============================================================================

local TextAreaBg = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
TextAreaBg:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 12, -92)
TextAreaBg:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -12, 90)
SetBackdropCustom(TextAreaBg, { 10/255, 10/255, 10/255, 1 }, { 40/255, 40/255, 40/255, 0.6 })

local ScrollFrame = CreateFrame("ScrollFrame", "RunawayAttScroll", TextAreaBg, "UIPanelScrollFrameTemplate")
ScrollFrame:SetPoint("TOPLEFT", TextAreaBg, "TOPLEFT", 8, -6)
ScrollFrame:SetPoint("BOTTOMRIGHT", TextAreaBg, "BOTTOMRIGHT", -28, 6)

local EditBox = CreateFrame("EditBox", "RunawayAttEditBox", ScrollFrame)
EditBox:SetMultiLine(true)
EditBox:SetAutoFocus(false)
EditBox:SetFontObject(GameFontHighlightSmall)
EditBox:SetWidth(680)
EditBox:SetTextColor(P.text[1], P.text[2], P.text[3])
EditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
ScrollFrame:SetScrollChild(EditBox)

-- ============================================================================
-- BOTTOM BUTTONS - ROW 1 (CSV)
-- ============================================================================

local row1Y = 56

local CaptureBtn = CreateStyledButton(MainFrame, "Capturar Raid", 130, 28, "primary")
CaptureBtn:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", 12, row1Y)
CaptureBtn:SetScript("OnClick", function()
    local data, err = CollectRaidRoster()
    if not data then
        StatusText:SetText("|cfff87171Erro:|r " .. (err or "Erro desconhecido"))
        InfoText:SetText("")
        EditBox:SetText("")
        return
    end

    local csv = GenerateCSV(data)
    EditBox:SetText(csv)
    EditBox:HighlightText()
    EditBox:SetFocus()

    local fmtName = RunawayRaidAttendanceDB.settings.csvFormat == "largo" and "Largo" or "Alto"
    StatusText:SetText("|cff4ade80Capturado!|r Ctrl+A → Ctrl+C → colar no site.")
    InfoText:SetText(string.format(
        "|cffa88080%s  •  %d presentes  •  %d ausentes  •  %s|r",
        data.date, data.totalPresent, data.totalAbsent, fmtName
    ))

    table.insert(RunawayRaidAttendanceDB.history, {
        date = data.date,
        playerCount = data.totalPresent + data.totalAbsent,
        present = data.totalPresent,
        absent = data.totalAbsent,
        format = RunawayRaidAttendanceDB.settings.csvFormat,
        csv = csv,
    })
    while #RunawayRaidAttendanceDB.history > 50 do
        table.remove(RunawayRaidAttendanceDB.history, 1)
    end

    print("|cffcc2020[Runaway]|r " .. data.totalPresent .. " presentes, " .. data.totalAbsent .. " ausentes (" .. fmtName .. ")")
end)

local SelectBtn = CreateStyledButton(MainFrame, "Selecionar Tudo", 120, 28)
SelectBtn:SetPoint("LEFT", CaptureBtn, "RIGHT", 6, 0)
SelectBtn:SetScript("OnClick", function()
    EditBox:HighlightText()
    EditBox:SetFocus()
    StatusText:SetText("|cff4ade80Selecionado!|r Pressione Ctrl+C.")
end)

local FormatBtn = CreateStyledButton(MainFrame, "Trocar Formato", 120, 28)
FormatBtn:SetPoint("LEFT", SelectBtn, "RIGHT", 6, 0)
FormatBtn:SetScript("OnClick", function()
    local s = RunawayRaidAttendanceDB.settings
    if s.csvFormat == "alto" then
        s.csvFormat = "largo"
    else
        s.csvFormat = "alto"
    end
    UpdateFormatLabel()
    local fmtName = s.csvFormat == "largo" and "Largo" or "Alto"
    StatusText:SetText("|cfffacc15Formato:|r " .. fmtName .. ". Capture novamente.")
    print("|cffcc2020[Runaway]|r Formato → " .. fmtName)
end)

local HistoryBtn = CreateStyledButton(MainFrame, "Ultimo Registro", 120, 28)
HistoryBtn:SetPoint("LEFT", FormatBtn, "RIGHT", 6, 0)
HistoryBtn:SetScript("OnClick", function()
    local h = RunawayRaidAttendanceDB.history
    if #h == 0 then
        StatusText:SetText("|cfffacc15Nenhum registro no historico.|r")
        return
    end
    local last = h[#h]
    EditBox:SetText(last.csv)
    EditBox:HighlightText()
    EditBox:SetFocus()
    StatusText:SetText("|cff4ade80Ultimo registro carregado.|r")
    InfoText:SetText(string.format("|cffa88080%s  •  %d presentes  •  %s|r",
        last.date, last.present, last.format == "largo" and "Largo" or "Alto"))
end)

-- ============================================================================
-- BOTTOM BUTTONS - ROW 2 (GUILD TOOLS)
-- ============================================================================

local row2Y = 18

-- Separator label
local ToolsLabel = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ToolsLabel:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", 14, row2Y + 6)
ToolsLabel:SetText("|cffa88080Guild:|r")

local InviteBtn = CreateStyledButton(MainFrame, "Invite Raid", 110, 26, "success")
InviteBtn:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", 54, row2Y)
InviteBtn:SetScript("OnClick", function()
    InviteGuildByRank(function(msg)
        StatusText:SetText(msg)
    end)
end)

InviteBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("|cffcc2020Invite Raid|r")
    GameTooltip:AddLine("Envia aviso no chat da guild:", 1, 1, 1)
    GameTooltip:AddLine("|cfffacc15\"Invites em 10s! Vem pra raid!\"|r", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Apos 10s, convida todos os membros", 1, 1, 1)
    GameTooltip:AddLine("online com rank |cff4ade800 a 6|r (incluindo Trial).", 1, 1, 1)
    GameTooltip:Show()
end)
InviteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local AssistBtn = CreateStyledButton(MainFrame, "Dar Assists", 110, 26, "success")
AssistBtn:SetPoint("LEFT", InviteBtn, "RIGHT", 6, 0)
AssistBtn:SetScript("OnClick", function()
    local count = PromoteAssists()
    StatusText:SetText(string.format("|cff4ade80%d jogadores promovidos|r a assistente (Ranks 2-3).", count))
    print("|cffcc2020[Runaway]|r " .. count .. " assists concedidos (Ranks 2 e 3).")
end)

AssistBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("|cffcc2020Dar Assists|r")
    GameTooltip:AddLine("Promove a assistente todos os", 1, 1, 1)
    GameTooltip:AddLine("membros da raid com |cff4ade80Rank 2 ou 3|r na guild.", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Requer ser lider ou assistente.", 0.6, 0.4, 0.4)
    GameTooltip:Show()
end)
AssistBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Separator
local Sep = MainFrame:CreateTexture(nil, "ARTWORK")
Sep:SetSize(1, 20)
Sep:SetPoint("LEFT", AssistBtn, "RIGHT", 10, 0)
Sep:SetColorTexture(P.border[1], P.border[2], P.border[3], 0.5)

-- Website link hint
local WebLabel = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
WebLabel:SetPoint("LEFT", Sep, "RIGHT", 10, 0)
WebLabel:SetText("|cffa88080raid.runaway.com.br|r")

-- ============================================================================
-- MINIMAP BUTTON
-- ============================================================================

local MinimapBtn = CreateFrame("Button", "RunawayMinimapButton", Minimap)
MinimapBtn:SetSize(32, 32)
MinimapBtn:SetFrameStrata("MEDIUM")
MinimapBtn:SetFrameLevel(8)
MinimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
MinimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
MinimapBtn:RegisterForDrag("LeftButton")

local MinimapIcon = MinimapBtn:CreateTexture(nil, "BACKGROUND")
MinimapIcon:SetSize(20, 20)
MinimapIcon:SetPoint("CENTER")
MinimapIcon:SetTexture("Interface\\Icons\\Ability_Mount_WhiteDireWolf")

local MinimapBorder = MinimapBtn:CreateTexture(nil, "OVERLAY")
MinimapBorder:SetSize(54, 54)
MinimapBorder:SetPoint("CENTER")
MinimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

MinimapBtn:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end
    elseif button == "RightButton" then
        CaptureBtn:Click()
        if not MainFrame:IsShown() then MainFrame:Show() end
    end
end)

MinimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffcc2020RUNAWAY|r Raid Attendance")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffffffEsquerdo:|r Abrir/fechar", 1, 1, 1)
    GameTooltip:AddLine("|cffffffffDireito:|r Captura rapida", 1, 1, 1)
    GameTooltip:Show()
end)
MinimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdateMinimapPos()
    local angle = RunawayRaidAttendanceDB.settings.minimapAngle or 220
    local r = 80
    MinimapBtn:ClearAllPoints()
    MinimapBtn:SetPoint("CENTER", Minimap, "CENTER",
        r * math.cos(math.rad(angle)),
        r * math.sin(math.rad(angle)))
end

MinimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        cx, cy = cx / s, cy / s
        RunawayRaidAttendanceDB.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
        UpdateMinimapPos()
    end)
end)
MinimapBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_RUNAWAY1 = "/runaway"
SLASH_RUNAWAY2 = "/rra"

SlashCmdList["RUNAWAY"] = function(msg)
    msg = string.lower(strtrim(msg or ""))

    if msg == "cap" or msg == "capture" then
        if not MainFrame:IsShown() then MainFrame:Show() end
        CaptureBtn:Click()
    elseif msg == "invite" or msg == "inv" then
        InviteGuildByRank(function(msg2)
            StatusText:SetText(msg2)
        end)
    elseif msg == "assist" then
        AssistBtn:Click()
    elseif msg == "largo" then
        RunawayRaidAttendanceDB.settings.csvFormat = "largo"
        UpdateFormatLabel()
        print("|cffcc2020[Runaway]|r Formato → Largo")
    elseif msg == "alto" then
        RunawayRaidAttendanceDB.settings.csvFormat = "alto"
        UpdateFormatLabel()
        print("|cffcc2020[Runaway]|r Formato → Alto")
    elseif msg == "history" or msg == "hist" then
        local h = RunawayRaidAttendanceDB.history
        if #h == 0 then
            print("|cffcc2020[Runaway]|r Nenhum registro.")
            return
        end
        print("|cffcc2020[Runaway]|r Historico (" .. #h .. "):")
        for i = math.max(1, #h - 9), #h do
            local e = h[i]
            print(string.format("  |cffa88080#%d|r %s - %d presentes (%s)",
                i, e.date, e.present, e.format == "largo" and "Largo" or "Alto"))
        end
    elseif msg == "reset" then
        RunawayRaidAttendanceDB.history = {}
        print("|cffcc2020[Runaway]|r Historico limpo.")
    elseif msg == "help" then
        print("|cffcc2020=== RUNAWAY Raid Attendance v2.0 ===|r")
        print("|cffcc2020/rra|r - Abrir/fechar janela")
        print("|cffcc2020/rra cap|r - Capturar attendance")
        print("|cffcc2020/rra invite|r - Avisar guild + convidar ranks 0-6")
        print("|cffcc2020/rra assist|r - Dar assist (ranks 2-3)")
        print("|cffcc2020/rra alto|r / |cffcc2020largo|r - Trocar formato CSV")
        print("|cffcc2020/rra history|r - Ver historico")
        print("|cffcc2020/rra reset|r - Limpar historico")
    else
        if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end
    end
end

-- ============================================================================
-- INIT
-- ============================================================================

local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        local db = RunawayRaidAttendanceDB
        db.history = db.history or {}
        db.settings = db.settings or {}
        db.settings.csvFormat = db.settings.csvFormat or "alto"
        db.settings.minimapAngle = db.settings.minimapAngle or 220

        UpdateFormatLabel()
        UpdateMinimapPos()

        print("|cffcc2020[RUNAWAY]|r Raid Attendance v2.0 carregado! |cffa88080/rra help|r")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
