@tool
class_name DKMaterialSet
extends Resource
## Ordered list of materials. Index 0 is always empty air (added for you).
## Cells store the index as one byte, so at most 255 real materials.

@export var materials: Array[DKMaterial] = []:
	set(v):
		materials = v
		_built = false

var _by_index: Array[DKMaterial] = []
var _index_of: Dictionary = {}
var _built := false


static func make(list: Array) -> DKMaterialSet:
	var s := DKMaterialSet.new()
	var typed: Array[DKMaterial] = []
	for m in list:
		typed.append(m)
	s.materials = typed
	return s


func _build() -> void:
	_by_index.clear()
	_index_of.clear()
	var air := DKMaterial.make(&"empty", 0, {"solid": false, "falls": false})
	_by_index.append(air)
	_index_of[air.id] = 0
	for m in materials:
		assert(m != null and m.id != &"", "DKMaterialSet: every material needs an id")
		assert(not _index_of.has(m.id), "DKMaterialSet: duplicate id %s" % m.id)
		assert(_by_index.size() < 256, "DKMaterialSet: max 255 materials")
		_index_of[m.id] = _by_index.size()
		_by_index.append(m)
	_built = true


func size() -> int:
	if not _built:
		_build()
	return _by_index.size()


func at(i: int) -> DKMaterial:
	if not _built:
		_build()
	return _by_index[i]


## Index for an id, or -1 if unknown.
func index_of(mat_id: StringName) -> int:
	if not _built:
		_build()
	return int(_index_of.get(mat_id, -1))
