-- TinyThreat 0.8.3
-- Threat-colored nameplates with customizable colors.
-- Threat percentage displayed on current valid NPC target.

local ADDON_NAME = "TinyThreat"
local VERSION = "0.8.3"

--------------------------------------------------
-- DEFAULTS
--------------------------------------------------

local defaults = {
    mode = "auto",

    display = {
        size = 13,
        font = 1,
        x = 0,
        y = 0,
    },

    colors = {
        green = { 0, 1, 0 },
        yellow = { 1, 1, 0 },
        red = { 1, 0, 0 },
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
        return target
    end

    if type(target) ~= "table" then
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
    if type(TinyThreatDB) ~= "table" then
        TinyThreatDB = {}
    end

    DB = CopyDefaults(defaults, TinyThreatDB)

    DB.display.refreshMs = nil
    DB.display.r = nil
    DB.display.g = nil
    DB.display.b = nil

    if DB.display.centeredDefaultVersion ~= 1 then
        DB.display.x = 0
        DB.display.y = 0
        DB.display.centeredDefaultVersion = 1
    end

    DB.display.align = nil

    for colorName, defaultColor in pairs(defaults.colors) do
        local saved = DB.colors[colorName]

        COLORS[colorName] = {
            saved[1] or defaultColor[1],
            saved[2] or defaultColor[2],
            saved[3] or defaultColor[3],
        }
    end

    TinyThreatDB = DB
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function Message(text)
    print("|cff33ff99TinyThreat:|r " .. tostring(text))
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

    if UnitIsPlayer(unit) then
        return false
    end

    if not UnitCanAttack("player", unit) then
        return false
    end

    if UnitIsDeadOrGhost(unit) then
        return false
    end

    if UnitIsPVP and UnitIsPVP(unit) then
        return false
    end

    if UnitIsPVPFreeForAll and UnitIsPVPFreeForAll(unit) then
        return false
    end

    return true
end

--------------------------------------------------
-- TANK DETECTION
--------------------------------------------------

local function IsTank()
    if not DB then
        return false
    end

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
        healthBar:SetStatusBarColor(
            color[1],
            color[2],
            color[3]
        )
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
    if not displayFrame or not healthBar or not DB then
        return
    end

    local text = displayFrame.text

    if not text then
        return
    end

    local offsetX = DB.display.x or 0
    local offsetY = DB.display.y or 0

    displayFrame:ClearAllPoints()
    displayFrame:SetAllPoints(healthBar)

    text:ClearAllPoints()

    text:SetPoint(
        "CENTER",
        displayFrame,
        "CENTER",
        offsetX,
        offsetY
    )

    text:SetWidth(math.max(1, healthBar:GetWidth()))
    text:SetHeight(math.max(1, healthBar:GetHeight()))

    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
end

local function GetThreatText(frame)
    if not frame then
        return nil
    end

    if frame.TinyThreatDisplay then
        return frame.TinyThreatDisplay
    end

    local healthBar = GetHealthBar(frame)

    if not healthBar then
        return nil
    end

    local displayFrame = CreateFrame(
        "Frame",
        nil,
        healthBar
    )

    displayFrame:SetAllPoints(healthBar)

    displayFrame:SetFrameLevel(
        healthBar:GetFrameLevel() + 10
    )

    local text = displayFrame:CreateFontString(
        nil,
        "OVERLAY"
    )

    text:SetPoint(
        "CENTER",
        displayFrame,
        "CENTER",
        0,
        0
    )

    text:SetWidth(math.max(1, healthBar:GetWidth()))
    text:SetHeight(math.max(1, healthBar:GetHeight()))

    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")

    displayFrame.text = text

    if not ApplyFontSettings(text) then
        displayFrame:Hide()
        return nil
    end

    text:SetText("")

    local threatColor = GetThreatColor(frame.unit)

    if threatColor then
        text:SetTextColor(
            threatColor[1],
            threatColor[2],
            threatColor[3]
        )
    end

    frame.TinyThreatDisplay = displayFrame
    frame.TinyThreatText = text

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

            if frame and frame.TinyThreatDisplay then
                frame.TinyThreatDisplay:Hide()
            end
        end
    end

    currentTargetFrame = nil
end

local function UpdateTargetThreatText()
    if not IsValidThreatTextTarget("target") then
        HideAllThreatTexts()
        return
    end

    local targetFrame = GetUnitFrame("target")

    if not targetFrame then
        HideAllThreatTexts()
        return
    end

    if currentTargetFrame and currentTargetFrame ~= targetFrame then
        if currentTargetFrame.TinyThreatDisplay then
            currentTargetFrame.TinyThreatDisplay:Hide()
        end

        currentTargetFrame = nil
    end

    local plates = C_NamePlate.GetNamePlates()

    if plates then
        for _, plate in ipairs(plates) do
            local frame = plate.UnitFrame

            if frame and frame ~= targetFrame
                and frame.TinyThreatDisplay then
                frame.TinyThreatDisplay:Hide()
            end
        end
    end

    local healthBar = GetHealthBar(targetFrame)

    if not healthBar then
        if targetFrame.TinyThreatDisplay then
            targetFrame.TinyThreatDisplay:Hide()
        end

        currentTargetFrame = nil
        return
    end

    local threat = GetThreat("target")

    if not threat or threat.otherPlayer then
        if targetFrame.TinyThreatDisplay then
            targetFrame.TinyThreatDisplay:Hide()
        end

        currentTargetFrame = nil
        return
    end

    local displayFrame = GetThreatText(targetFrame)

    if not displayFrame then
        return
    end

    local text = targetFrame.TinyThreatText

    if not text or not ApplyFontSettings(text) then
        displayFrame:Hide()
        return
    end

    local threatColor = GetThreatColor("target")

    if threatColor then
        text:SetTextColor(
            threatColor[1],
            threatColor[2],
            threatColor[3]
        )
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
    if not DB or not frame then
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

local LAYOUT = {
    width = 310,

    paddingTop = 48,
    paddingBottom = 20,
    paddingLeft = 20,
    paddingRight = 20,

    gap = 14,
    labelToControlGap = 7,

    sliderGroupHeight = 58,
    labelHeight = 18,
    dropdownHeight = 32,
    colorRowHeight = 58,
    buttonHeight = 25,
}

--------------------------------------------------
-- LAYOUT MANAGER
--------------------------------------------------

local function CreateLayout(parent, settings)
    local layout = {
        parent = parent,
        settings = settings,
        cursorY = -settings.paddingTop,
    }

    function layout:Add(element, height, extraGap)
        element:ClearAllPoints()

        element:SetPoint(
            "TOPLEFT",
            self.parent,
            "TOPLEFT",
            self.settings.paddingLeft,
            self.cursorY
        )

        element:SetWidth(
            self.settings.width
            - self.settings.paddingLeft
            - self.settings.paddingRight
        )

        self.cursorY = self.cursorY
            - height
            - (extraGap or self.settings.gap)
    end

    function layout:GetRequiredHeight()
    return math.abs(self.cursorY)
        + self.settings.paddingBottom
    end

    return layout
end

--------------------------------------------------
-- UI HELPERS
--------------------------------------------------

local function CreateLabel(parent, text)
    local label = parent:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormal"
    )

    label:SetText(text)
    label:SetJustifyH("LEFT")

    return label
end

local function CreateDropdown(parent, name, layout, labelText, width)
    local label = CreateLabel(parent, labelText)
    layout:Add(label, LAYOUT.labelHeight, LAYOUT.labelToControlGap)

    local dropdown = CreateFrame(
        "Frame",
        name,
        parent,
        "UIDropDownMenuTemplate"
    )

    local availableWidth = LAYOUT.width
        - LAYOUT.paddingLeft
        - LAYOUT.paddingRight

    -- Let the layout manager establish the initial position.
    layout:Add(dropdown, LAYOUT.dropdownHeight)

    -- Set the actual dropdown button width.
    UIDropDownMenu_SetWidth(
        dropdown,
        width or (availableWidth - 16)
    )

    -- Compensate for the template's built-in left offset.
    local point, relativeTo, relativePoint, x, y = dropdown:GetPoint(1)

    dropdown:ClearAllPoints()
    dropdown:SetPoint(
        point,
        relativeTo,
        relativePoint,
        x - 16,
        y
    )

    local dropdownText = _G[name .. "Text"]
    if dropdownText then
        dropdownText:SetJustifyH("LEFT")
    end

    return dropdown
end

--------------------------------------------------
-- SLIDERS
--------------------------------------------------

local function CreateSlider(
    parent,
    layout,
    labelText,
    minValue,
    maxValue,
    step,
    getter,
    setter
)
    local group = CreateFrame("Frame", nil, parent)
    group:SetHeight(LAYOUT.sliderGroupHeight)

    local label = CreateLabel(group, labelText)

    label:SetPoint(
        "TOPLEFT",
        group,
        "TOPLEFT",
        0,
        0
    )

    local valueText = group:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )

    valueText:SetPoint(
        "TOPRIGHT",
        group,
        "TOPRIGHT",
        0,
        0
    )

    local slider = CreateFrame(
        "Slider",
        nil,
        group,
        "OptionsSliderTemplate"
    )

    slider:SetPoint(
        "TOPLEFT",
        group,
        "TOPLEFT",
        0,
        -LAYOUT.labelToControlGap - LAYOUT.labelHeight
    )

    slider:SetPoint(
        "TOPRIGHT",
        group,
        "TOPRIGHT",
        0,
        -LAYOUT.labelToControlGap - LAYOUT.labelHeight
    )

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

        TinyThreatDB = DB
        RefreshAll()
    end)

    slider:SetValue(getter())
    valueText:SetText(FormatValue(getter()))

    layout:Add(group, LAYOUT.sliderGroupHeight)

    return slider, valueText
end

--------------------------------------------------
-- COLOR PICKERS
--------------------------------------------------

local function UpdateColorSwatch(button, color)
    if not button or not button.swatch then
        return
    end

    button.swatch:SetColorTexture(
        color[1],
        color[2],
        color[3],
        1
    )
end

local function ApplyCustomColor(colorName, r, g, b)
    if not DB then
        return
    end

    r = Clamp(r, 0, 1)
    g = Clamp(g, 0, 1)
    b = Clamp(b, 0, 1)

    DB.colors[colorName] = { r, g, b }

    COLORS[colorName] = { r, g, b }

    TinyThreatDB = DB

    local button = _G["TinyThreatColorButton_" .. colorName]

    if button then
        UpdateColorSwatch(button, COLORS[colorName])
    end

    RefreshAll()
end

local function OpenThreatColorPicker(colorName, button)
    local current = DB.colors[colorName]

    local previous = {
        current[1],
        current[2],
        current[3],
    }

    local function ApplyColor(r, g, b)
        ApplyCustomColor(colorName, r, g, b)
    end

    local info = {
        r = current[1],
        g = current[2],
        b = current[3],

        hasOpacity = false,

        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()

            ApplyColor(r, g, b)
        end,

        cancelFunc = function()
            ApplyColor(
                previous[1],
                previous[2],
                previous[3]
            )
        end,
    }

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.hasOpacity = false

        ColorPickerFrame.func = info.swatchFunc
        ColorPickerFrame.cancelFunc = info.cancelFunc

        ColorPickerFrame:SetColorRGB(
            current[1],
            current[2],
            current[3]
        )

        ColorPickerFrame:Show()
    end
end

local function CreateColorPickerRow(parent, layout)
    local group = CreateFrame("Frame", nil, parent)
    group:SetHeight(LAYOUT.colorRowHeight)

    local title = CreateLabel(group, "Threat colors")
    title:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)

    local names = {
        { key = "green", label = "Safe" },
        { key = "yellow", label = "Warning" },
        { key = "red", label = "Aggro" },
    }

    local totalWidth = LAYOUT.width
        - LAYOUT.paddingLeft
        - LAYOUT.paddingRight

    local itemWidth = totalWidth / #names

    for index, item in ipairs(names) do
        local column = CreateFrame("Frame", nil, group)
        column:SetSize(itemWidth, 34)
        column:SetPoint(
            "TOPLEFT",
            group,
            "TOPLEFT",
            (index - 1) * itemWidth,
            -22
        )

        -- Each label stays within its own column, above its color picker.
        local label = column:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )
        label:SetPoint("TOPLEFT", column, "TOPLEFT", 0, 0)
        label:SetWidth(itemWidth - 4)
        label:SetHeight(14)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(item.label)

        local button = CreateFrame(
            "Button",
            nil,
            column,
            "BackdropTemplate"
        )
        button:SetSize(itemWidth - 4, 18)
        button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)

        button.swatch = button:CreateTexture(nil, "ARTWORK")
        button.swatch:SetAllPoints(button)

        UpdateColorSwatch(button, COLORS[item.key])

        button:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
        })

        button:SetScript("OnClick", function()
            OpenThreatColorPicker(item.key, button)
        end)

        _G["TinyThreatColorButton_" .. item.key] = button
    end

    layout:Add(group, LAYOUT.colorRowHeight)
end

--------------------------------------------------
-- CONFIGURATION WINDOW
--------------------------------------------------

local function CreateConfigWindow()
    if configFrame then
        return
    end

    configFrame = CreateFrame(
        "Frame",
        "TinyThreatConfig",
        UIParent,
        "BasicFrameTemplateWithInset"
    )

    configFrame:SetWidth(LAYOUT.width)
    configFrame:SetHeight(300)
    configFrame:SetPoint("CENTER")

    configFrame:SetFrameStrata("DIALOG")

    configFrame:SetFrameLevel(
        UIParent:GetFrameLevel() + 100
    )

    configFrame:SetToplevel(true)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")

    configFrame:SetScript(
        "OnDragStart",
        configFrame.StartMoving
    )

    configFrame:SetScript(
        "OnDragStop",
        configFrame.StopMovingOrSizing
    )

    configFrame.TitleText:SetText("TinyThreat")

    local layout = CreateLayout(
        configFrame,
        LAYOUT
    )

    --------------------------------------------------
    -- FONT DROPDOWN
    --------------------------------------------------

    local fontDropdown = CreateDropdown(
        configFrame,
        "TinyThreatFontDropdown",
        layout,
        "Font",
        nil
    )

    UIDropDownMenu_Initialize(
        fontDropdown,
        function(self, level)
            for index, fontInfo in ipairs(FONTS) do
                local info = UIDropDownMenu_CreateInfo()

                info.text = fontInfo.name
                info.value = index

                info.checked = (
                    DB.display.font == index
                )

                info.func = function()
                    DB.display.font = index

                    UIDropDownMenu_SetSelectedValue(
                        fontDropdown,
                        index
                    )

                    UIDropDownMenu_SetText(
                        fontDropdown,
                        fontInfo.name
                    )

                    TinyThreatDB = DB

                    RefreshAll()
                end

                UIDropDownMenu_AddButton(
                    info,
                    level
                )
            end
        end
    )

    local selectedFont = FONTS[DB.display.font] or FONTS[1]

    UIDropDownMenu_SetSelectedValue(
        fontDropdown,
        DB.display.font
    )

    UIDropDownMenu_SetText(
        fontDropdown,
        selectedFont.name
    )

    --------------------------------------------------
    -- COLOR PICKERS
    --------------------------------------------------

    CreateColorPickerRow(
        configFrame,
        layout
    )

    --------------------------------------------------
    -- FONT SIZE
    --------------------------------------------------

    local fontSizeSlider = CreateSlider(
        configFrame,
        layout,
        "Font Size",
        8,
        32,
        1,

        function()
            return DB.display.size
        end,

        function(value)
            DB.display.size = value
        end
    )

    --------------------------------------------------
    -- X POSITION
    --------------------------------------------------

    local xPositionSlider = CreateSlider(
        configFrame,
        layout,
        "X Position",
        -100,
        100,
        1,

        function()
            return DB.display.x
        end,

        function(value)
            DB.display.x = value
        end
    )

    --------------------------------------------------
    -- Y POSITION
    --------------------------------------------------

    local yPositionSlider = CreateSlider(
        configFrame,
        layout,
        "Y Position",
        -100,
        100,
        1,

        function()
            return DB.display.y
        end,

        function(value)
            DB.display.y = value
        end
    )

    --------------------------------------------------
    -- RESET BUTTON
    --------------------------------------------------

    local resetButton = CreateFrame(
        "Button",
        nil,
        configFrame,
        "UIPanelButtonTemplate"
    )

    resetButton:SetHeight(LAYOUT.buttonHeight)

    resetButton:SetText("Reset to Defaults")

    layout:Add(
        resetButton,
        LAYOUT.buttonHeight,
        0
    )

    resetButton:SetScript(
        "OnClick",
        function()

            DB.display.size = defaults.display.size
            DB.display.font = defaults.display.font
            DB.display.x = defaults.display.x
            DB.display.y = defaults.display.y

            for colorName, defaultColor in pairs(defaults.colors) do

                DB.colors[colorName] = {
                    defaultColor[1],
                    defaultColor[2],
                    defaultColor[3],
                }

                COLORS[colorName] = {
                    defaultColor[1],
                    defaultColor[2],
                    defaultColor[3],
                }

                local button = _G[
                    "TinyThreatColorButton_" .. colorName
                ]

                if button then
                    UpdateColorSwatch(
                        button,
                        COLORS[colorName]
                    )
                end
            end

            fontSizeSlider:SetValue(
                defaults.display.size
            )

            xPositionSlider:SetValue(
                defaults.display.x
            )

            yPositionSlider:SetValue(
                defaults.display.y
            )

            UIDropDownMenu_SetSelectedValue(
                fontDropdown,
                defaults.display.font
            )

            UIDropDownMenu_SetText(
                fontDropdown,
                FONTS[defaults.display.font].name
            )

            TinyThreatDB = DB

            RefreshAll()

            Message("Settings reset.")
        end
    )

    --------------------------------------------------
    -- AUTOMATIC WINDOW HEIGHT
    --------------------------------------------------

    configFrame:SetHeight(
        layout:GetRequiredHeight()
    )

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
    local button = CreateFrame(
        "Button",
        "TinyThreatMinimapButton",
        Minimap
    )

    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")

    button:SetPoint(
        "TOPLEFT",
        Minimap,
        "TOPLEFT",
        0,
        0
    )

    button:SetNormalTexture(
        "Interface\\Icons\\Ability_Hunter_MarkedForDeath"
    )

    button:SetHighlightTexture(
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
    )

    button:RegisterForClicks(
        "LeftButtonUp",
        "RightButtonUp"
    )

    button:SetScript(
        "OnClick",
        function(_, mouseButton)
            if mouseButton == "RightButton" then
                Message("Version " .. VERSION)
            else
                ToggleConfig()
            end
        end
    )

    button:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("TinyThreat")
            GameTooltip:AddLine(
                "Left-click: Open settings",
                1,
                1,
                1
            )
            GameTooltip:AddLine(
                "Right-click: Show version",
                1,
                1,
                1
            )
            GameTooltip:Show()
        end
    )

    button:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )
end

--------------------------------------------------
-- SLASH COMMANDS
--------------------------------------------------

SLASH_TinyThreat1 = "/TinyThreat"
SLASH_TinyThreat2 = "/tt"

SlashCmdList["TinyThreat"] = function(message)

    local command, argument =
        message:match("^(%S*)%s*(.-)$")

    command = string.lower(command or "")
    argument = string.lower(argument or "")

    if command == "mode" then

        if argument == "auto"
            or argument == "tank"
            or argument == "dps" then

            DB.mode = argument

            TinyThreatDB = DB

            Message("Mode changed: " .. argument)

            RefreshAll()

        else
            Message("Usage: /tt mode auto|tank|dps")
        end

    elseif command == "version" then

        Message("Version " .. VERSION)

    elseif command == "config"
        or command == "settings" then

        ToggleConfig()

    else

        Message("TinyThreat " .. VERSION)
        Message("/tt config - Open settings")
        Message("/tt mode auto - Automatic role detection")
        Message("/tt mode tank - Tank mode")
        Message("/tt mode dps - DPS mode")
        Message("/tt version - Show version")

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

eventFrame:SetScript(
    "OnEvent",
    function(_, event, unit)

        if event == "PLAYER_LOGIN" then

            InitializeDB()

            CreateConfigWindow()

            if hooksecurefunc then
                hooksecurefunc(
                    "CompactUnitFrame_UpdateHealthColor",
                    function(frame)
                        UpdateHealthBarColor(frame)
                    end
                )
            end

            C_Timer.NewTicker(
                0.5,
                RefreshAll
            )

            Message("Version " .. VERSION .. " loaded.")

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

            if frame and frame.TinyThreatDisplay then
                frame.TinyThreatDisplay:Hide()
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
    end
)