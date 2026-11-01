-- ThreatTint 0.7.4
-- Fixed refresh interval: 500 ms.
-- Threat-colored nameplates.
-- Threat percentage is displayed only on the current attackable,
-- non-player, non-PvP-tagged NPC target.

local ADDON_NAME = "ThreatTint"
local VERSION = "0.7.4"

local defaults = {
    mode = "auto",

    display = {
        size = 13,
        font = 1,
        x = 8,
        y = 0,
        align = "RIGHT",
    },
}

local DB
local currentTargetFrame

local FONTS = {
    { name = "Friz Quadrata (Standard)", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
    { name = "Skurri", path = "Fonts\\skurri.ttf" },
    { name = "2002", path = "Fonts\\2002.TTF" },
    { name = "2002 Bold", path = "Fonts\\2002B.TTF" },
}

local COLORS = {
    green = { 0, 1, 0 },
    yellow = { 1, 1, 0 },
    red = { 1, 0, 0 },
    gray = { 0.5, 0.5, 0.5 },
}

--------------------------------------------------
-- DATABASE
--------------------------------------------------

local function CopyDefaults(source, target)
    if type(source) ~= "table" then
        target = {}
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = CopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

local function InitializeDB()
    if type(ThreatTintDB) ~= "table" then
        ThreatTintDB = {}
    end

    DB = CopyDefaults(defaults, ThreatTintDB)
    DB.display.refreshMs = nil -- Alte einstellbare Refresh-Rate entfernen.
    DB.display.r = nil
    DB.display.g = nil
    DB.display.b = nil
    if DB.display.align == "LEFT" and DB.display.x == -8 then
        DB.display.align = defaults.display.align
        DB.display.x = defaults.display.x
    end
    ThreatTintDB = DB
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function Message(text)
    print("|cff33ff99ThreatTint:|r " .. tostring(text))
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function GetUnitFrame(unit)
    if not unit then
        return nil
    end

    local plate = C_NamePlate.GetNamePlateForUnit(unit)

    if not plate then
        return nil
    end

    return plate.UnitFrame
end

local function GetHealthBar(frame)
    if not frame then
        return nil
    end

    return frame.healthBar
        or frame.healthbar
        or frame.HealthBar
end

--------------------------------------------------
-- TARGET FILTER
--------------------------------------------------

local function IsValidThreatTextTarget(unit)
    if not unit or not UnitExists(unit) then
        return false
    end

    -- Keine Spieler anzeigen.
    if UnitIsPlayer(unit) then
        return false
    end

    -- Nur NPCs anzeigen, die angegriffen werden können.
    if not UnitCanAttack("player", unit) then
        return false
    end

    -- Tote Ziele ausschließen.
    if UnitIsDeadOrGhost(unit) then
        return false
    end

    -- PvP-markierte Ziele ausschließen.
    if UnitIsPVP and UnitIsPVP(unit) then
        return false
    end

    -- Zusätzliche Absicherung für PvP-Flags, falls verfügbar.
    if UnitIsPVPFreeForAll and UnitIsPVPFreeForAll(unit) then
        return false
    end

    return true
end

--------------------------------------------------
-- TANK DETECTION
--------------------------------------------------

local function IsTank()
    if DB.mode == "tank" then
        return true
    end

    if DB.mode == "dps" then
        return false
    end

    if IsInGroup() and UnitGroupRolesAssigned then
        if UnitGroupRolesAssigned("player") == "TANK" then
            return true
        end
    end

    local _, class = UnitClass("player")

    if class == "WARRIOR" then
        local stance = GetShapeshiftFormID and GetShapeshiftFormID()

        if stance == 71 then
            return true
        end
    end

    if class == "DRUID" then
        local stance = GetShapeshiftFormID and GetShapeshiftFormID()

        if stance == 5487 or stance == 9634 then
            return true
        end
    end

    if class == "PALADIN" and UnitBuff then
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellID =
                UnitBuff("player", i)

            if not name then
                break
            end

            if spellID == 25780 then
                return true
            end
        end
    end

    return false
end

--------------------------------------------------
-- THREAT INFORMATION
--------------------------------------------------

local function GetThreat(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end

    if UnitIsPlayer(unit) then
        return {
            otherPlayer = true,
        }
    end

    local isTanking
    local status
    local scaledPercent
    local rawPercent

    if UnitDetailedThreatSituation then
        isTanking, status, scaledPercent, rawPercent =
            UnitDetailedThreatSituation("player", unit)
    end

    if status == nil and UnitThreatSituation then
        status = UnitThreatSituation("player", unit)
    end

    local percent = scaledPercent or rawPercent

    if percent == nil then
        if status == 0 then
            percent = 0
        elseif status == 1 then
            percent = 50
        elseif status == 2 then
            percent = 80
        elseif status == 3 then
            percent = 100
        else
            percent = 0
        end
    end

    return {
        isTanking = isTanking,
        status = status,
        percent = percent,
    }
end

--------------------------------------------------
-- NAMEPLATE COLORS
--------------------------------------------------

local function GetThreatColor(unit)
    local threat = GetThreat(unit)

    if not threat then
        return nil
    end

    if threat.otherPlayer then
        return COLORS.gray
    end

    local tank = IsTank()
    local percent = threat.percent or 0
    local hasAggro = threat.isTanking or threat.status == 3

    if tank then
        if hasAggro then
            return COLORS.green
        elseif percent >= 80 then
            return COLORS.yellow
        else
            return COLORS.red
        end
    else
        if hasAggro then
            return COLORS.red
        elseif percent >= 80 then
            return COLORS.yellow
        else
            return COLORS.green
        end
    end
end

local function UpdateHealthBarColor(frame)
    if not frame or not frame.unit then
        return
    end

    local healthBar = GetHealthBar(frame)

    if not healthBar or not healthBar.SetStatusBarColor then
        return
    end

    local color = GetThreatColor(frame.unit)

    if color then
        healthBar:SetStatusBarColor(color[1], color[2], color[3])
    end
end

--------------------------------------------------
-- THREAT TEXT
--------------------------------------------------

local function ApplyFontSettings(text)
    if not text or not DB then
        return false
    end

    local display = DB.display
    local fontInfo = FONTS[display.font] or FONTS[1]
    local fontSize = Clamp(display.size, 8, 32)

    local success, result = pcall(
        text.SetFont,
        text,
        fontInfo.path,
        fontSize,
        "OUTLINE"
    )

    if not success or result == false then
        local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

        success, result = pcall(
            text.SetFont,
            text,
            fallback,
            fontSize,
            "OUTLINE"
        )
    end

    return success and result ~= false
end

local function ApplyThreatPosition(displayFrame, healthBar)
    if not displayFrame or not healthBar then
        return
    end

    local text = displayFrame.text
    if not text then
        return
    end

    local alignment = DB.display.align or "RIGHT"
    if alignment ~= "LEFT" and alignment ~= "CENTER" and alignment ~= "RIGHT" then
        alignment = "RIGHT"
    end

    local offsetX = DB.display.x
    if offsetX == nil then
        offsetX = 8
    end

    local offsetY = DB.display.y or 0

    -- Anchor the FontString itself directly to the health bar.
    -- With RIGHT alignment and a positive X offset, the text's right
    -- edge sits just outside the nameplate and the text grows leftward.
    text:ClearAllPoints()
    text:SetPoint(alignment, healthBar, alignment, offsetX, offsetY)
    text:SetJustifyH(alignment)
end

local function GetThreatText(frame)
    if not frame then
        return nil
    end

    if frame.ThreatTintDisplay then
        return frame.ThreatTintDisplay
    end

    local displayFrame = CreateFrame("Frame", nil, UIParent)
    displayFrame:SetSize(100, 30)
    displayFrame:SetFrameStrata("TOOLTIP")
    displayFrame:SetFrameLevel(100)

    local text = displayFrame:CreateFontString(nil, "OVERLAY")
    text:SetWidth(100)
    text:SetHeight(30)
    text:SetJustifyH(DB.display.align or "RIGHT")
    text:SetJustifyV("MIDDLE")
    displayFrame.text = text

    if not ApplyFontSettings(text) then
        displayFrame:Hide()
        return nil
    end

    text:SetText("")

    local threatColor = GetThreatColor(frame.unit)
    if threatColor then
        text:SetTextColor(threatColor[1], threatColor[2], threatColor[3])
    end

    frame.ThreatTintDisplay = displayFrame
    frame.ThreatTintText = text

    return displayFrame
end

local function HideAllThreatTexts()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end

    local plates = C_NamePlate.GetNamePlates()

    if plates then
        for _, plate in ipairs(plates) do
            local frame = plate.UnitFrame

            if frame and frame.ThreatTintDisplay then
                frame.ThreatTintDisplay:Hide()
            end
        end
    end

    currentTargetFrame = nil
end

local function UpdateTargetThreatText()
    -- Kein gültiges Target: alle Anzeigen ausblenden.
    if not IsValidThreatTextTarget("target") then
        HideAllThreatTexts()
        return
    end

    local targetFrame = GetUnitFrame("target")

    if not targetFrame then
        HideAllThreatTexts()
        return
    end

    -- Alte Anzeige beim Targetwechsel sofort entfernen.
    if currentTargetFrame and currentTargetFrame ~= targetFrame then
        if currentTargetFrame.ThreatTintDisplay then
            currentTargetFrame.ThreatTintDisplay:Hide()
        end

        currentTargetFrame = nil
    end

    -- Sicherheit: Alle anderen Nameplates bleiben ohne Prozentanzeige.
    local plates = C_NamePlate.GetNamePlates()

    if plates then
        for _, plate in ipairs(plates) do
            local frame = plate.UnitFrame

            if frame and frame ~= targetFrame and frame.ThreatTintDisplay then
                frame.ThreatTintDisplay:Hide()
            end
        end
    end

    local healthBar = GetHealthBar(targetFrame)

    if not healthBar then
        if targetFrame.ThreatTintDisplay then
            targetFrame.ThreatTintDisplay:Hide()
        end

        currentTargetFrame = nil
        return
    end

    local threat = GetThreat("target")

    if not threat or threat.otherPlayer then
        if targetFrame.ThreatTintDisplay then
            targetFrame.ThreatTintDisplay:Hide()
        end

        currentTargetFrame = nil
        return
    end

    local displayFrame = GetThreatText(targetFrame)

    if not displayFrame then
        return
    end

    local text = targetFrame.ThreatTintText

    if not text or not ApplyFontSettings(text) then
        displayFrame:Hide()
        return
    end

    local threatColor = GetThreatColor("target")
    if threatColor then
        text:SetTextColor(threatColor[1], threatColor[2], threatColor[3])
    end

    local percent = math.floor((threat.percent or 0) + 0.5)

    text:SetText(percent .. "%")

    ApplyThreatPosition(displayFrame, healthBar)

    displayFrame:Show()
    currentTargetFrame = targetFrame
end

--------------------------------------------------
-- REFRESH
--------------------------------------------------

local function RefreshNameplate(frame)
    if not frame then
        return
    end

    UpdateHealthBarColor(frame)
end

local function RefreshAll()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end

    local plates = C_NamePlate.GetNamePlates()

    if plates then
        for _, plate in ipairs(plates) do
            if plate.UnitFrame then
                RefreshNameplate(plate.UnitFrame)
            end
        end
    end

    UpdateTargetThreatText()
end


--------------------------------------------------
-- CONFIGURATION WINDOW
--------------------------------------------------

local configFrame

local function CreateLabel(parent, text, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 20, y)
    label:SetText(text)

    return label
end

local function CreateSlider(
    parent,
    labelText,
    y,
    minValue,
    maxValue,
    step,
    getter,
    setter
)
    CreateLabel(parent, labelText, y)

    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, y)

    local slider = CreateFrame(
        "Slider",
        nil,
        parent,
        "OptionsSliderTemplate"
    )

    slider:SetPoint("TOPLEFT", 20, y - 25)
    slider:SetWidth(270)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local function FormatValue(value)
        if step >= 1 then
            return tostring(math.floor(value + 0.5))
        end

        return string.format("%.2f", value)
    end

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step

        setter(value)
        valueText:SetText(FormatValue(value))

        RefreshAll()
    end)

    slider:SetValue(getter())
    valueText:SetText(FormatValue(getter()))

    return slider
end



local function CreateConfigWindow()
    if configFrame then
        return
    end

    configFrame = CreateFrame(
        "Frame",
        "ThreatTintConfig",
        UIParent,
        "BasicFrameTemplateWithInset"
    )

    configFrame:SetSize(310, 440)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetFrameLevel(UIParent:GetFrameLevel() + 100)
    configFrame:SetToplevel(true)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")

    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)

    configFrame.TitleText:SetText("ThreatTint Einstellungen")

    CreateLabel(configFrame, "Anzeige-Einstellungen", -45)

    CreateLabel(configFrame, "Schriftart", -80)

    local fontDropdown = CreateFrame(
        "Frame",
        "ThreatTintFontDropdown",
        configFrame,
        "UIDropDownMenuTemplate"
    )
    fontDropdown:SetPoint("TOPLEFT", 5, -105)
    UIDropDownMenu_SetWidth(fontDropdown, 170)

    UIDropDownMenu_Initialize(fontDropdown, function(self, level)
        for index, fontInfo in ipairs(FONTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = fontInfo.name
            info.value = index
            info.checked = (DB.display.font == index)
            info.func = function()
                DB.display.font = index
                UIDropDownMenu_SetSelectedValue(fontDropdown, index)
                UIDropDownMenu_SetText(fontDropdown, fontInfo.name)
                RefreshAll()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local selectedFont = FONTS[DB.display.font] or FONTS[1]
    UIDropDownMenu_SetSelectedValue(fontDropdown, DB.display.font)
    UIDropDownMenu_SetText(fontDropdown, selectedFont.name)

    CreateLabel(configFrame, "Textausrichtung", -155)

    local alignmentDropdown = CreateFrame(
        "Frame",
        "ThreatTintAlignmentDropdown",
        configFrame,
        "UIDropDownMenuTemplate"
    )
    alignmentDropdown:SetPoint("TOPLEFT", 5, -180)
    UIDropDownMenu_SetWidth(alignmentDropdown, 170)

    local alignmentOptions = {
        { value = "LEFT", text = "Links" },
        { value = "CENTER", text = "Zentriert" },
        { value = "RIGHT", text = "Rechts" },
    }

    UIDropDownMenu_Initialize(alignmentDropdown, function(self, level)
        for _, option in ipairs(alignmentOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = (DB.display.align == option.value)
            info.func = function()
                DB.display.align = option.value
                UIDropDownMenu_SetSelectedValue(alignmentDropdown, option.value)
                UIDropDownMenu_SetText(alignmentDropdown, option.text)
                RefreshAll()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local selectedAlignment = DB.display.align or "LEFT"
    local alignmentText = "Links"
    for _, option in ipairs(alignmentOptions) do
        if option.value == selectedAlignment then
            alignmentText = option.text
            break
        end
    end
    UIDropDownMenu_SetSelectedValue(alignmentDropdown, selectedAlignment)
    UIDropDownMenu_SetText(alignmentDropdown, alignmentText)

    CreateSlider(
        configFrame,
        "Schriftgröße",
        -225,
        8,
        32,
        1,
        function() return DB.display.size end,
        function(value) DB.display.size = value end
    )

    CreateSlider(
        configFrame,
        "Horizontale Position",
        -285,
        -100,
        100,
        1,
        function() return DB.display.x end,
        function(value) DB.display.x = value end
    )

    CreateSlider(
        configFrame,
        "Vertikale Position",
        -345,
        -100,
        100,
        1,
        function() return DB.display.y end,
        function(value) DB.display.y = value end
    )



    local resetButton = CreateFrame(
        "Button",
        nil,
        configFrame,
        "UIPanelButtonTemplate"
    )

    resetButton:SetSize(155, 25)
    resetButton:SetPoint("BOTTOMLEFT", 20, 15)
    resetButton:SetText("Einstellungen zurücksetzen")

    resetButton:SetScript("OnClick", function()
        DB.display.size = defaults.display.size
        DB.display.font = defaults.display.font
        DB.display.x = defaults.display.x
        DB.display.y = defaults.display.y
        DB.display.align = defaults.display.align

        UIDropDownMenu_SetSelectedValue(alignmentDropdown, DB.display.align)
        UIDropDownMenu_SetText(alignmentDropdown, "Links")
        UIDropDownMenu_SetSelectedValue(fontDropdown, DB.display.font)
        UIDropDownMenu_SetText(fontDropdown, FONTS[DB.display.font].name)

        RefreshAll()

        configFrame:Hide()

        Message("Einstellungen zurückgesetzt.")
    end)

    local closeButton = CreateFrame(
        "Button",
        nil,
        configFrame,
        "UIPanelButtonTemplate"
    )

    closeButton:SetSize(90, 25)
    closeButton:SetPoint("BOTTOMRIGHT", -20, 15)
    closeButton:SetText("Schließen")

    closeButton:SetScript("OnClick", function()
        configFrame:Hide()
    end)

    configFrame:Hide()
end

local function ToggleConfig()
    if not configFrame then
        CreateConfigWindow()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end

--------------------------------------------------
-- MINIMAP BUTTON
--------------------------------------------------

local function CreateMinimapButton()
    local button = CreateFrame("Button", "ThreatTintMinimapButton", Minimap)

    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)

    button:SetNormalTexture("Interface\\Icons\\Ability_Hunter_MarkedForDeath")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            Message("Version " .. VERSION)
        else
            ToggleConfig()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ThreatTint")
        GameTooltip:AddLine("Linksklick: Einstellungen", 1, 1, 1)
        GameTooltip:AddLine("Rechtsklick: Version", 1, 1, 1)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

--------------------------------------------------
-- SLASH COMMANDS
--------------------------------------------------

SLASH_THREATTINT1 = "/threattint"
SLASH_THREATTINT2 = "/tt"

SlashCmdList["THREATTINT"] = function(message)
    local command, argument = message:match("^(%S*)%s*(.-)$")

    command = string.lower(command or "")
    argument = string.lower(argument or "")

    if command == "mode" then
        if argument == "auto" or argument == "tank" or argument == "dps" then
            DB.mode = argument
            Message("Modus geändert: " .. argument)
            RefreshAll()
        else
            Message("Verwendung: /tt mode auto|tank|dps")
        end

    elseif command == "version" then
        Message("Version " .. VERSION)

    elseif command == "config" or command == "settings" then
        ToggleConfig()

    else
        Message("ThreatTint " .. VERSION)
        Message("/tt config - Einstellungen öffnen")
        Message("/tt mode auto - Automatische Erkennung")
        Message("/tt mode tank - Tank-Modus")
        Message("/tt mode dps - DPS-Modus")
        Message("/tt version - Version anzeigen")
    end
end

--------------------------------------------------
-- EVENTS
--------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        InitializeDB()

        CreateConfigWindow()
        CreateMinimapButton()

        if hooksecurefunc then
            hooksecurefunc(
                "CompactUnitFrame_UpdateHealthColor",
                function(frame)
                    UpdateHealthBarColor(frame)
                end
            )
        end


        C_Timer.NewTicker(0.5, RefreshAll)

        Message("Version " .. VERSION .. " geladen.")

        RefreshAll()

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local frame = GetUnitFrame(unit)

        if frame then
            RefreshNameplate(frame)
        end

        UpdateTargetThreatText()

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        local frame = plate and plate.UnitFrame

        if frame and frame.ThreatTintDisplay then
            frame.ThreatTintDisplay:Hide()
        end

        if frame == currentTargetFrame then
            currentTargetFrame = nil
        end

        UpdateTargetThreatText()

    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateTargetThreatText()

    else
        RefreshAll()
    end
end)