@tool
class_name DKMaterial
extends Resource
## One cell material. All gameplay numbers are integers so results are
## identical on every machine (deterministic for replays and local co-op).

## Unique id, e.g. &"dirt". Index 0 in a DKMaterialSet is always empty air.
@export var id: StringName = &""
## Hit points per cell (integer). Damage subtracts from this.
@export var hp: int = 100
## Weight per cell (used by support/stress modules; unused by the core ops).
@export var density: int = 1
## Material a falling piece of this material becomes when it lands
## (e.g. &"rubble"). Empty = stays the same material.
@export var rubble_into: StringName = &""
## Share (0..100) of a landed piece's cells that turn into `rubble_into`
## (chosen by a deterministic hash; the piece's bottom row always does). The
## rest keep their material at half hp, so a fallen wall reads as broken.
@export var rubble_pct: int = 100
## Debris particles per destroyed cell (cosmetic, DKDebris).
@export var debris_count: int = 2
## Load a cell can carry (used by support/stress modules).
@export var strength: int = 10
## Blocks movement and shots.
@export var solid: bool = true
## Indestructible and counts as ground for support ("anchor").
@export var anchor: bool = false
## Can come loose and fall when unsupported.
@export var falls: bool = true
## Per-damage-type resistance in percent: {&"blast": 50, &"fire": 100}.
## 100 = immune, 0 = full damage. Missing types = 0.
@export var resist: Dictionary = {}
## Optional: destroying this cell sets off a blast (read by the Pro chain
## module; the core ignores it). 0 = not explosive.
@export var blast_radius: float = 0.0
@export var blast_power: int = 0
## Optional fire data (read by the Pro fire module; the core ignores it).
## Ticks a cell burns before it is gone; 0 = not flammable.
@export var burn_ticks: int = 0
## Chance in percent that a burning neighbour sets this cell alight per spread check.
@export var ignite_pct: int = 0
## Material a burnt-out cell turns into (e.g. &"ash"); empty = destroyed.
@export var ash_into: StringName = &""
## Presentation hints for adapters (debris colour, sound layer).
@export var debris_color: Color = Color(0.5, 0.45, 0.4)
@export var sound_class: StringName = &""


static func make(p_id: StringName, p_hp: int, extra: Dictionary = {}) -> DKMaterial:
	var m := DKMaterial.new()
	m.id = p_id
	m.hp = p_hp
	for k: String in extra:
		m.set(k, extra[k])
	return m


## Effective damage after resistance (integer, never negative).
func damage_after_resist(power: int, damage_type: StringName) -> int:
	var r: int = clampi(int(resist.get(damage_type, 0)), 0, 100)
	return maxi(0, power * (100 - r) / 100)
