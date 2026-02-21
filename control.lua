script.on_init(function()
    storage.active_group     = {}
    storage.pending          = {}
    storage.tool_filters     = {}  -- [item_number] = {[item_name] = {comparator, quality}}
    storage.pending_drag     = {}  -- [player_index] = filters snapshot for drag
    storage.spawn_on_confirm = {}  -- [player_index] = bool
    storage.pending_filters  = {}  -- [player_index] = temp filters when in spawn_on_confirm mode
    storage.editing_id       = {}  -- [player_index] = item_number of planner currently open in GUI
end)

script.on_load(function() end)

-- ─────────────────────────────────────────────
--  Constants
-- ─────────────────────────────────────────────

local SLOTS         = 10
local SEL_STYLE     = "yellow_slot_button"
local NORM_STYLE    = "slot_button"

local QUALITY_ORDER = { "normal", "uncommon", "rare", "epic", "legendary" }
local QUALITY_LEVEL = { normal=1, uncommon=2, rare=3, epic=4, legendary=5 }
local COMPARATORS   = { "* (any)", "=", "≠", ">", "≥", "<", "≤" }

local ANY_QUALITY_SPRITE = "item-dropper-any-quality"

-- ─────────────────────────────────────────────
--  Per-tool filter storage via item_number
-- ─────────────────────────────────────────────

-- Only used when picking up a planner from inventory or deleting it
local function find_planner(player)
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == "item-dropper-tool" then
        return cursor
    end
    local inv = player.get_main_inventory()
    if inv then
        local stack = inv.find_item_stack("item-dropper-tool")
        if stack then return stack end
    end
    return nil
end

local function get_filters(player)
    storage.editing_id = storage.editing_id or {}
    local id = storage.editing_id[player.index]
    if not id then return {} end
    storage.tool_filters = storage.tool_filters or {}
    return storage.tool_filters[id] or {}
end

local function set_filters(player, filters)
    storage.editing_id = storage.editing_id or {}
    local id = storage.editing_id[player.index]
    if not id then return end
    storage.tool_filters = storage.tool_filters or {}
    storage.tool_filters[id] = filters
end

local function clear_editing_id(player)
    storage.editing_id = storage.editing_id or {}
    storage.editing_id[player.index] = nil
end

-- ─────────────────────────────────────────────
--  Spawn on confirm helpers
-- ─────────────────────────────────────────────

local function is_spawn_mode(player)
    storage.spawn_on_confirm = storage.spawn_on_confirm or {}
    return storage.spawn_on_confirm[player.index] == true
end

local function get_pending_filters(player)
    storage.pending_filters = storage.pending_filters or {}
    return storage.pending_filters[player.index] or {}
end

local function set_pending_filters(player, filters)
    storage.pending_filters = storage.pending_filters or {}
    storage.pending_filters[player.index] = filters
end

-- Called when GUI closes — spawn planner only if filters were set
local function maybe_spawn(player)
    if not is_spawn_mode(player) then return end
    storage.spawn_on_confirm[player.index] = false
    local filters = get_pending_filters(player)
    set_pending_filters(player, {})
    if not next(filters) then return end  -- nothing selected, don't spawn
    local inv = player.get_main_inventory()
    if not inv then return end
    local empty = inv.find_empty_stack()
    if not empty then
        player.print("No room in inventory for Item Dropper Planner.")
        return
    end
    empty.set_stack{ name = "item-dropper-tool", count = 1 }
    local id = empty.item_number
    if id then
        storage.tool_filters = storage.tool_filters or {}
        storage.tool_filters[id] = filters
    end
    -- editing_id is not set in spawn mode, nothing to clear
end

-- ─────────────────────────────────────────────
--  Drag tool
-- ─────────────────────────────────────────────

local function activate_drag_tool(player)
    local filters = is_spawn_mode(player) and get_pending_filters(player) or get_filters(player)
    storage.pending_drag = storage.pending_drag or {}
    storage.pending_drag[player.index] = filters
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == "item-dropper-tool" then
        local inv = player.get_main_inventory()
        if inv then
            local empty = inv.find_empty_stack()
            if empty then cursor.swap_stack(empty) end
        end
    end
    player.cursor_stack.set_stack{ name = "item-dropper-selection", count = 1 }
end

-- ─────────────────────────────────────────────
--  Quality helpers
-- ─────────────────────────────────────────────

local function is_any(comparator)
    return comparator == "any" or comparator == "* (any)"
end

local function quality_matches(item_quality, comparator, filter_quality)
    if is_any(comparator) then return true end
    local iq = QUALITY_LEVEL[item_quality] or 1
    local fq = QUALITY_LEVEL[filter_quality] or 1
    if comparator == "="  then return iq == fq end
    if comparator == "≠"  then return iq ~= fq end
    if comparator == ">"  then return iq >  fq end
    if comparator == "≥"  then return iq >= fq end
    if comparator == "<"  then return iq <  fq end
    if comparator == "≤"  then return iq <= fq end
    return false
end

-- ─────────────────────────────────────────────
--  Item helpers
-- ─────────────────────────────────────────────

local function is_valid_item(item)
    if item.hidden then return false end
    if item.has_flag("only-in-cursor") then return false end
    if not item.group then return false end
    if item.group.name == "other" then return false end
    return true
end

local function get_groups()
    local groups, seen = {}, {}
    for _, item in pairs(prototypes.item) do
        if is_valid_item(item) then
            local g = item.group
            if not seen[g.name] then
                seen[g.name] = true
                table.insert(groups, g)
            end
        end
    end
    table.sort(groups, function(a, b) return a.order < b.order end)
    return groups
end

local function get_items_in_group(group_name)
    local items = {}
    for _, item in pairs(prototypes.item) do
        if is_valid_item(item) and item.group and item.group.name == group_name then
            table.insert(items, item)
        end
    end
    table.sort(items, function(a, b)
        if a.subgroup.order ~= b.subgroup.order then return a.subgroup.order < b.subgroup.order end
        return a.order < b.order
    end)
    return items
end

-- ─────────────────────────────────────────────
--  Slot tooltip
-- ─────────────────────────────────────────────

local function slot_tooltip(item_name, comparator, quality)
    local proto    = prototypes.item[item_name]
    local name_str = proto and proto.localised_name or item_name
    if is_any(comparator) then
        return {"", name_str, "\nQuality: Any\n[font=default-semibold][color=red]Click to remove[/color][/font]"}
    else
        local q_proto = prototypes.quality[quality]
        local q_name  = q_proto and q_proto.localised_name or quality
        return {"", name_str, "\nQuality: ", comparator, " ", q_name, "\n[font=default-semibold][color=red]Click to remove[/color][/font]"}
    end
end

-- ─────────────────────────────────────────────
--  Refresh filter slot row
-- ─────────────────────────────────────────────

local function refresh_filter_slots(frame, selected_items)
    local slots_flow = frame.main_flow.filter_slots_frame.slots_flow
    local selected = {}
    for name, filter in pairs(selected_items) do
        table.insert(selected, { name=name, comparator=filter.comparator, quality=filter.quality })
    end
    table.sort(selected, function(a, b) return a.name < b.name end)
    slots_flow.clear()
    for i = 1, SLOTS do
        local s = selected[i]
        if s then
            local btn = slots_flow.add{
                type    = "sprite-button",
                name    = "filter_slot_" .. s.name,
                sprite  = "item/" .. s.name,
                tooltip = slot_tooltip(s.name, s.comparator, s.quality),
                style   = NORM_STYLE,
                tags    = { filter_slot = true, item_name = s.name },
            }
            local has_badge = not is_any(s.comparator) and (s.comparator ~= "=" or s.quality ~= "normal")
            local has_any   = is_any(s.comparator)
            if has_badge or has_any then
                local overlay = btn.add{ type = "flow", direction = "horizontal", ignored_by_interaction = true }
                overlay.style.size = {36, 36}
                overlay.style.vertical_align = "bottom"
                overlay.style.horizontal_align = "left"
                overlay.style.padding = 1
                if has_any then
                    local icon = overlay.add{ type = "sprite", sprite = ANY_QUALITY_SPRITE, ignored_by_interaction = true }
                    icon.style.size = 16
                    icon.style.bottom_padding = 2
                    icon.resize_to_sprite = false
                else
                    if s.comparator ~= "=" then
                        local lbl = overlay.add{ type = "label", caption = s.comparator, ignored_by_interaction = true }
                        lbl.style.font = "count-font"
                        lbl.style.font_color = {r=1, g=1, b=1}
                    end
                    local icon = overlay.add{ type = "sprite", sprite = "quality/" .. s.quality, ignored_by_interaction = true }
                    icon.style.size = 16
                    icon.style.bottom_padding = 2
                    icon.resize_to_sprite = false
                end
            end
        else
            slots_flow.add{ type = "sprite-button", name = "filter_slot_empty_" .. i, style = NORM_STYLE, enabled = false }
        end
    end
    local overflow = frame.main_flow.filter_slots_frame.overflow_label
    local extra = #selected - SLOTS
    if extra > 0 then
        overflow.caption = "+" .. extra .. " more"
        overflow.visible = true
    else
        overflow.visible = false
    end
end

-- ─────────────────────────────────────────────
--  Build item grid
-- ─────────────────────────────────────────────

local function build_item_grid(grid_frame, group_name, selected_items)
    grid_frame.clear()
    local items = get_items_in_group(group_name)
    for _, item in ipairs(items) do
        local sel = selected_items[item.name]
        grid_frame.add{
            type    = "sprite-button",
            name    = "item_btn_" .. item.name,
            sprite  = "item/" .. item.name,
            tooltip = item.localised_name,
            style   = sel and SEL_STYLE or NORM_STYLE,
            tags    = { item_btn = true, item_name = item.name },
        }
    end
end

-- ─────────────────────────────────────────────
--  Build quality bar
-- ─────────────────────────────────────────────

local function build_quality_bar(bar_flow, pending)
    bar_flow.clear()
    local dd = bar_flow.add{
        type           = "drop-down",
        name           = "quality_comparator_dd",
        items          = COMPARATORS,
        selected_index = 1,
    }
    dd.style.height = 28
    for i, c in ipairs(COMPARATORS) do
        if c == pending.comparator then dd.selected_index = i break end
    end
    for _, q in ipairs(QUALITY_ORDER) do
        local q_proto = prototypes.quality[q]
        if q_proto then
            local active = (not is_any(pending.comparator) and pending.quality == q)
            local btn = bar_flow.add{
                type    = "sprite-button",
                name    = "quality_btn_" .. q,
                sprite  = "quality/" .. q,
                tooltip = q_proto.localised_name,
                style   = active and SEL_STYLE or NORM_STYLE,
                tags    = { quality_btn = true, quality_name = q },
            }
            btn.style.size = 28
        end
    end
end

-- ─────────────────────────────────────────────
--  Create GUI
-- ─────────────────────────────────────────────

local function create_gui(player, spawn_mode)
    storage.active_group     = storage.active_group     or {}
    storage.pending          = storage.pending          or {}
    storage.spawn_on_confirm = storage.spawn_on_confirm or {}
    storage.pending_filters  = storage.pending_filters  or {}
    storage.editing_id       = storage.editing_id       or {}

    if player.gui.screen.item_dropper_frame then
        player.gui.screen.item_dropper_frame.destroy()
        return
    end

    local selected_items
    if spawn_mode then
        storage.spawn_on_confirm[player.index] = true
        storage.pending_filters[player.index]  = {}
        selected_items = {}
    else
        -- editing_id may already be set by on_player_cursor_stack_changed before
        -- create_gui is called — trust it if present, otherwise find the planner
        if not storage.editing_id[player.index] then
            local stack = find_planner(player)
            if not stack then
                player.print("You need an Item Dropper Planner in your inventory to open the GUI.")
                return
            end
            storage.editing_id[player.index] = stack.item_number
        end
        storage.spawn_on_confirm[player.index] = false
        selected_items = get_filters(player)
    end

    local groups      = get_groups()
    local first_group = groups[1] and groups[1].name or ""
    storage.active_group[player.index] = storage.active_group[player.index] or first_group
    local active_group = storage.active_group[player.index]

    storage.pending[player.index] = storage.pending[player.index] or { comparator = "* (any)", quality = "normal" }
    local pending = storage.pending[player.index]

    local frame = player.gui.screen.add{ type = "frame", name = "item_dropper_frame", direction = "vertical" }
    frame.auto_center = true
    frame.style.minimal_width = 450
    player.opened = frame

    -- title bar
    local titlebar = frame.add{ type = "flow", direction = "horizontal" }
    titlebar.drag_target = frame
    titlebar.style.horizontal_spacing = 8
    titlebar.style.height = 28
    titlebar.add{ type = "label", caption = {"item-name.item-dropper-tool"}, style = "frame_title", ignored_by_interaction = true }
    local filler = titlebar.add{ type = "empty-widget", ignored_by_interaction = true }
    filler.style.horizontally_stretchable = true
    if not spawn_mode then
        titlebar.add{ type = "sprite-button", name = "item_dropper_delete", sprite = "utility/trash", style = "close_button", tooltip = "Delete this Item Dropper Planner" }
    end
    titlebar.add{ type = "sprite-button", name = "item_dropper_close", sprite = "utility/close", style = "close_button", tooltip = {"gui.close"} }

    local main_flow = frame.add{ type = "flow", name = "main_flow", direction = "vertical" }
    main_flow.style.vertical_spacing = 8

    -- filter slots
    local filter_frame = main_flow.add{ type = "frame", name = "filter_slots_frame", direction = "vertical", style = "inside_shallow_frame_with_padding" }
    filter_frame.add{ type = "label", caption = "[font=default-bold]Selected items[/font]" }
    local sf = filter_frame.add{ type = "flow", name = "slots_flow", direction = "horizontal" }
    sf.style.horizontal_spacing = 2
    local overflow = filter_frame.add{ type = "label", name = "overflow_label", caption = "" }
    overflow.style.font_color = { r=0.7, g=0.7, b=0.7 }
    overflow.visible = false

    -- group tabs
    local tabs_flow = main_flow.add{ type = "flow", name = "group_tabs_flow", direction = "horizontal" }
    tabs_flow.style.horizontal_spacing = 2
    for _, group in ipairs(groups) do
        tabs_flow.add{
            type    = "sprite-button",
            name    = "group_tab_" .. group.name,
            sprite  = "item-group/" .. group.name,
            tooltip = group.localised_name,
            style   = (group.name == active_group) and SEL_STYLE or NORM_STYLE,
            tags    = { group_tab = true, group_name = group.name },
        }
    end

    -- item grid
    local grid_outer = main_flow.add{ type = "frame", name = "grid_outer", style = "inside_shallow_frame_with_padding" }
    local grid_scroll = grid_outer.add{ type = "scroll-pane", name = "grid_scroll", direction = "vertical" }
    grid_scroll.style.maximal_height = 322
    grid_scroll.style.minimal_width  = 420
    local grid = grid_scroll.add{ type = "table", name = "item_grid", column_count = 10 }
    build_item_grid(grid, active_group, selected_items)

    -- quality bar
    local qbar_frame = main_flow.add{ type = "frame", name = "quality_bar_frame", style = "inside_shallow_frame_with_padding" }
    local qbar = qbar_frame.add{ type = "flow", name = "quality_bar", direction = "horizontal" }
    qbar.style.horizontal_spacing = 4
    qbar.style.vertical_align = "center"
    build_quality_bar(qbar, pending)

    -- "Use" button
    local use_flow = main_flow.add{ type = "flow", direction = "horizontal" }
    use_flow.style.horizontal_align = "right"
    use_flow.add{
        type    = "button",
        name    = "item_dropper_use",
        caption = "Use [drag to select area]",
        style   = "confirm_button",
        tooltip = "Put the selection tool in your cursor to drag over containers.",
    }

    refresh_filter_slots(frame, selected_items)
end

-- ─────────────────────────────────────────────
--  Events
-- ─────────────────────────────────────────────

script.on_event(defines.events.on_player_alt_selected_area, function(event)
    if event.item ~= "item-dropper-selection" then return end
    create_gui(game.players[event.player_index], false)
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name ~= "item-dropper-shortcut" then return end
    create_gui(game.players[event.player_index], true)
end)

script.on_event(defines.events.on_gui_closed, function(event)
    if event.gui_type ~= defines.gui_type.custom then return end
    local player = game.players[event.player_index]
    local frame  = player.gui.screen.item_dropper_frame
    if frame and frame.valid then
        maybe_spawn(player)
        clear_editing_id(player)
        frame.destroy()
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    local el = event.element
    if not el.valid then return end
    local player = game.players[event.player_index]
    local frame  = player.gui.screen.item_dropper_frame
    if not frame then return end

    local spawn_mode     = is_spawn_mode(player)
    local selected_items = spawn_mode and get_pending_filters(player) or get_filters(player)
    local pending        = storage.pending[event.player_index] or { comparator = "* (any)", quality = "normal" }

    if el.name == "item_dropper_close" then
        maybe_spawn(player)
        clear_editing_id(player)
        player.opened = nil
        frame.destroy()
        return
    end

    if el.name == "item_dropper_delete" then
        local id = storage.editing_id and storage.editing_id[player.index]
        if id then storage.tool_filters[id] = nil end
        clear_editing_id(player)
        local cursor = player.cursor_stack
        if cursor and cursor.valid_for_read and cursor.name == "item-dropper-tool" then
            cursor.clear()
        else
            local inv = player.get_main_inventory()
            if inv then inv.remove{ name = "item-dropper-tool", count = 1 } end
        end
        storage.spawn_on_confirm[player.index] = false
        player.opened = nil
        frame.destroy()
        return
    end

    if el.name == "item_dropper_use" then
        maybe_spawn(player)
        clear_editing_id(player)
        player.opened = nil
        frame.destroy()
        activate_drag_tool(player)
        return
    end

    if el.tags and el.tags.group_tab then
        local gn = el.tags.group_name
        storage.active_group[event.player_index] = gn
        build_item_grid(frame.main_flow.grid_outer.grid_scroll.item_grid, gn, selected_items)
        for _, btn in pairs(frame.main_flow.group_tabs_flow.children) do
            if btn.tags and btn.tags.group_tab then
                btn.style = (btn.tags.group_name == gn) and SEL_STYLE or NORM_STYLE
            end
        end
        return
    end

    if el.tags and el.tags.item_btn then
        local item_name = el.tags.item_name
        local new_filter = { comparator = pending.comparator, quality = pending.quality }
        if spawn_mode then
            selected_items[item_name] = new_filter
            set_pending_filters(player, selected_items)
        else
            selected_items[item_name] = new_filter
            set_filters(player, selected_items)
        end
        el.style = SEL_STYLE
        refresh_filter_slots(frame, selected_items)
        return
    end

    if el.tags and el.tags.filter_slot then
        local item_name = el.tags.item_name
        selected_items[item_name] = nil
        if spawn_mode then
            set_pending_filters(player, selected_items)
        else
            set_filters(player, selected_items)
        end
        local grid_btn = frame.main_flow.grid_outer.grid_scroll.item_grid["item_btn_" .. item_name]
        if grid_btn and grid_btn.valid then grid_btn.style = NORM_STYLE end
        refresh_filter_slots(frame, selected_items)
        return
    end

    if el.tags and el.tags.quality_btn then
        pending.quality = el.tags.quality_name
        if is_any(pending.comparator) then pending.comparator = "=" end
        storage.pending[event.player_index] = pending
        build_quality_bar(frame.main_flow.quality_bar_frame.quality_bar, pending)
        return
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local el = event.element
    if not el.valid or el.name ~= "quality_comparator_dd" then return end
    local player = game.players[event.player_index]
    local frame  = player.gui.screen.item_dropper_frame
    if not frame then return end
    local pending = storage.pending[event.player_index] or { comparator = "* (any)", quality = "normal" }
    pending.comparator = COMPARATORS[el.selected_index]
    if is_any(pending.comparator) then pending.quality = "normal" end
    storage.pending[event.player_index] = pending
    build_quality_bar(frame.main_flow.quality_bar_frame.quality_bar, pending)
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.players[event.player_index]
    local cursor = player.cursor_stack
    if not (cursor and cursor.valid_for_read and cursor.name == "item-dropper-tool") then return end
    local inv = player.get_main_inventory()
    if inv then
        local empty = inv.find_empty_stack()
        if empty then
            local id = cursor.item_number
            cursor.swap_stack(empty)
            storage.editing_id = storage.editing_id or {}
            storage.editing_id[player.index] = id
        end
    end
    create_gui(player, false)
end)

-- ─────────────────────────────────────────────
--  Inventory scanning
-- ─────────────────────────────────────────────

local inventory_ids = {
    defines.inventory.chest,
    defines.inventory.linked_container_main,
    defines.inventory.logistic_chest_storage,
    defines.inventory.logistic_chest_requester,
    defines.inventory.logistic_chest_buffer,
    defines.inventory.logistic_chest_active_provider,
    defines.inventory.logistic_chest_passive_provider,
    defines.inventory.roboport_robot,
    defines.inventory.roboport_material,
    defines.inventory.assembling_machine_input,
    defines.inventory.assembling_machine_output,
    defines.inventory.assembling_machine_modules,
    defines.inventory.assembling_machine_trash,
    defines.inventory.furnace_source,
    defines.inventory.furnace_result,
    defines.inventory.furnace_modules,
    defines.inventory.furnace_trash,
    defines.inventory.lab_input,
    defines.inventory.lab_trash,
    defines.inventory.mining_drill_modules,
    defines.inventory.beacon_modules,
    defines.inventory.turret_ammo,
    defines.inventory.rocket_silo_rocket,
    defines.inventory.rocket_silo_result,
    defines.inventory.car_trunk,
    defines.inventory.car_ammo,
    defines.inventory.cargo_wagon,
    defines.inventory.spider_trunk,
    defines.inventory.spider_ammo,
    defines.inventory.spider_trash,
    defines.inventory.proxy_main,
    defines.inventory.crafter_input,
    defines.inventory.crafter_output,
    defines.inventory.crafter_modules,
    defines.inventory.crafter_trash,
    defines.inventory.asteroid_collector_output,
    defines.inventory.agricultural_tower_input,
    defines.inventory.agricultural_tower_output,
}

local function process_entity(entity, selected_items)
    if not entity.valid then return end
    for _, inv_id in pairs(inventory_ids) do
        local inv = entity.get_inventory(inv_id)
        if inv then
            for i = 1, #inv do
                local stack = inv[i]
                if stack.valid_for_read then
                    local filter = selected_items[stack.name]
                    if filter then
                        local item_quality = stack.quality and stack.quality.name or "normal"
                        if quality_matches(item_quality, filter.comparator, filter.quality) then
                            entity.surface.spill_item_stack{
                                position      = entity.position,
                                stack         = { name = stack.name, count = stack.count, quality = stack.quality },
                                enable_looted = true,
                                force         = entity.force,
                                allow_belts   = false,
                            }
                            stack.clear()
                        end
                    end
                end
            end
        end
    end
end

script.on_event(defines.events.on_player_selected_area, function(event)
    if event.item ~= "item-dropper-selection" then return end
    local player = game.players[event.player_index]
    storage.pending_drag = storage.pending_drag or {}
    local selected_items = storage.pending_drag[player.index] or {}
    if not next(selected_items) then
        player.print("No items selected in the Item Dropper filter.")
        return
    end
    for _, entity in pairs(event.entities) do
        process_entity(entity, selected_items)
    end
end)