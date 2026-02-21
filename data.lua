-- Register any-quality icon as a named sprite
data:extend{{
    type = "sprite",
    name = "item-dropper-any-quality",
    filename = "__core__/graphics/icons/any-quality.png",
    size = 64,
    mipmap_count = 4,
    flags = {"icon"},
}}

-- Item Dropper planner: item-with-tags, lives in inventory
data:extend{{
    type = "item-with-tags",
    name = "item-dropper-tool",
    icon = "__item-dropper__/item-dropper-planner.png",
    icon_size = 64,
    icon_mipmaps = 4,
    flags = {"not-stackable", "spawnable"},
    stack_size = 1,
    weight = 0,
}}

-- Hidden selection tool: only used while dragging
data:extend{{
    type = "selection-tool",
    name = "item-dropper-selection",
    icon = "__item-dropper__/item-in-container.png",
    icon_size = 64,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    stack_size = 1,
    weight = 0,
    select = {
        border_color = {r = 1, g = 0.5, b = 0},
        cursor_box_type = "entity",
        mode = {"any-entity"},
        entity_type_filters = {
            "container", "linked-container", "logistic-container",
            "roboport", "assembling-machine", "furnace", "rocket-silo",
            "lab", "mining-drill", "beacon", "ammo-turret", "car",
            "cargo-wagon", "spider-vehicle", "crafter",
            "agricultural-tower", "asteroid-collector",
        },
    },
    alt_select = {
        border_color = {r = 1, g = 0.8, b = 0},
        cursor_box_type = "entity",
        mode = {"any-entity"},
        entity_type_filters = {
            "container", "linked-container", "logistic-container",
            "roboport", "assembling-machine", "furnace", "rocket-silo",
            "lab", "mining-drill", "beacon", "ammo-turret", "car",
            "cargo-wagon", "spider-vehicle", "crafter",
            "agricultural-tower", "asteroid-collector",
        },
    },
}}

-- Shortcut button
data:extend{{
    type = "shortcut",
    name = "item-dropper-shortcut",
    action = "lua",
    icon = "__item-dropper__/item-in-container.png",
    icon_size = 64,
    small_icon = "__item-dropper__/item-in-container.png",
    small_icon_size = 64,
    style = "red",
}}