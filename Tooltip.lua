--------------------------------------------------------------------------------
-- Cys's Guild Hall - "Guild crafters" line on item tooltips,
-- and "Not learned in the guild" on recipe items nobody in the guild knows
--------------------------------------------------------------------------------
local GH = CysGuildHall

local function AddLine(tooltip, data)
    if not GH.db or not GH.db.settings.tooltip or not GH.Index then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local id = data and data.id
    if not id then return end
    -- recipe items: "Not learned in the guild" when nobody has the recipe yet
    if GH.Index.RecipeItemGap then
        local name = C_Item.GetItemNameByID(id)
        if (not name or name == "") and data.lines and data.lines[1] then name = data.lines[1].leftText end
        if GH.Index.RecipeItemGap(id, name) then
            tooltip:AddLine("Not learned in the guild", 0.85, 0.64, 0.13)
        end
    end
    -- raid prep targets this item is part of
    local prep = GH.Prep and GH.Prep.TooltipLines(id)
    for _, line in ipairs(prep or {}) do
        tooltip:AddLine("|cffd9a421Raid prep:|r " .. line, 1, 1, 1, true)
    end
    local crafters = GH.Index.CraftersOfItem(id)
    if not crafters or #crafters == 0 then return end
    local names = {}
    for i = 1, math.min(4, #crafters) do
        local c = crafters[i]
        local r, g, b = 0.55, 0.55, 0.55   -- offline: grey
        if c.online then r, g, b = GH.ClassColor(c.name) end
        local extra = c.chars and ((" |cff8a8a8a+%d alt%s|r"):format(#c.chars - 1, #c.chars > 2 and "s" or "")) or ""
        names[i] = ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, GH.Short(c.name)) .. extra
    end
    local text = table.concat(names, ", ")
    if #crafters > 4 then text = text .. (" |cff8a8a8a+%d|r"):format(#crafters - 4) end
    tooltip:AddLine("|cffd9a421Guild crafters:|r " .. text, 1, 1, 1, true)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddLine)
end
