class_name DKReport
extends RefCounted
## Result of one damage request.

## Indices of destroyed cells, in deterministic (row-major) order.
var destroyed := PackedInt32Array()
## Material index each destroyed cell had (parallel to `destroyed`); handy
## for debris colours, sound layers and explosive materials.
var destroyed_mat := PackedByteArray()
## Cells that took damage (including destroyed ones).
var damaged := 0
## Indices of cells that took damage but survived (row-major), so adapters can
## update cracks / hp views without re-scanning the shape.
var damaged_cells := PackedInt32Array()
## Cells skipped because they are anchors, protected or fully resistant.
var blocked := 0
## Destroyed cells per material id: {&"dirt": 12}.
var by_material: Dictionary = {}
var instigator_id := 0
var damage_type: StringName = &""
var tag: StringName = &""


func destroyed_count() -> int:
	return destroyed.size()


func is_empty() -> bool:
	return damaged == 0
