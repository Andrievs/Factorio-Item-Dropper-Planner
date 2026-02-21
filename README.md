# Container Inventory Dropper

A Factorio 2.0 mod that lets you quickly drop specific items from container inventories onto the ground, with support for quality filtering.

## Features

- **Item filtering** — select which items to drop from containers
- **Quality filtering** — filter by quality with comparators (`=`, `≠`, `>`, `≥`, `<`, `≤`, or Any)
- **Multiple planners** — create as many planners as you need, each with independent filter configs
- **Drag to select** — drag over an area to drop matching items from all containers within it
- Works with chests, logistic containers, assembling machines, furnaces, roboports, cars, spidertrons, cargo wagons, and more

## How to Use

1. Click the **Item Dropper** shortcut button in the toolbar (or press the assigned key)
2. Select the items you want to drop using the item grid
3. Optionally set a quality filter using the comparator dropdown and quality buttons
4. Click **Use [drag to select area]** to get the selection tool
5. Drag over containers — matching items will be spilled onto the ground instantly

## Tips

- Open an existing planner by clicking it in your inventory
- Each planner remembers its own filter configuration independently
- Use the trash icon in the GUI title bar to delete a planner
- If you close the GUI without selecting any items, no planner is added to your inventory
- Items are dropped synchronously in a single tick — no bots, no race conditions

## Requirements

- Factorio 2.0.48+
- Space Age 2.0.48+

## FAQ

**Why drop items to the ground instead of having bots pick them up directly?**

When using bots to remove items from a container (like a roboport), the bot targets a specific inventory slot position. If other items are removed between the bot receiving the order and arriving at the container, the inventory shifts — the bot may end up collecting the wrong item entirely. This is a race condition that gets worse the more items are being moved at once.

This mod drops items synchronously in a single game tick — everything happens instantly with no window for inventory positions to shift. Items land on the ground immediately, and from there normal logistics (bots, belts, or manual pickup) can move them wherever they need to go. This separation of concerns is both more reliable and simpler.

**Why are there two separate items — the planner and the selection tool?**

Ideally this mod would work like the vanilla deconstruction planner — a single item that both stores filter configuration and acts as a drag selection tool. However, that behaviour is hardcoded into the game engine for vanilla planner types and is not available to mods.

The workaround is two items:
- **Item Dropper Planner** (`item-with-tags`) — lives in your inventory, stores filter configuration per instance via a unique item number
- **Item Dropper Selection** (hidden `selection-tool`) — only exists in your cursor while dragging, discarded immediately after

When you click "Use", the planner is safely moved back to inventory and the hidden selection tool is placed in your cursor. After dragging, the selection tool is gone and your planner remains in inventory unchanged. From the player's perspective it behaves as one seamless tool.

## License

MIT — see [LICENSE](LICENSE)