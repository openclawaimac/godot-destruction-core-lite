class_name DKFeel
extends Node
## Basic game feel for destruction: trauma screen shake, hitstop capped per
## chain, and a reduced-motion setting. Bind it to a DKWorld (and optionally
## a Camera2D); it reacts to detonations, big destructions and landings.
##
## - Shake: trauma (0..1) is added by events and decays over time; the
##   offset is `max_offset * trauma²` along a smooth deterministic wobble.
## - Hitstop: `request_hitstop(ms, chain_key)` grants at most ONE hitstop per
##   chain key (a 30-blast chain freezes once, not 30 times), never longer
##   than `hitstop_max_ms`, and not again within `hitstop_cooldown_ms`.
##   Lite detonations have no chain (key = their own id); the Pro chain module
##   puts its chain id in det["chain"], which is used as the key.
## - Reduced motion: no shake, no hitstop (accessibility setting).
##
## Timing uses real (unscaled) milliseconds so hitstop ends on time even when
## it slows Engine.time_scale. Tests drive it with `advance(ms)`.

signal shake_changed(offset: Vector2)
signal hitstop_started(ms: float, chain_key: Variant)
signal hitstop_ended()

@export var reduced_motion := false
@export var max_offset := 7.0
## Trauma lost per second.
@export var trauma_decay := 1.4
## Hitstop for a detonation (scaled by radius in `on_detonated`).
@export var hitstop_ms := 55.0
@export var hitstop_max_ms := 90.0
@export var hitstop_cooldown_ms := 140.0
## While in hitstop, Engine.time_scale is set to this (when `use_time_scale`).
@export var hitstop_time_scale := 0.05
@export var use_time_scale := true
## Camera to shake (its `offset` is set). Optional: listen to shake_changed.
@export var camera: Camera2D
## Process automatically (real time). Turn off and call advance() in tests.
@export var auto_process := true

var trauma := 0.0
var offset := Vector2.ZERO
var hitstop_left_ms := 0.0
var hitstops_granted := 0

var _clock_ms := 0.0
var _cooldown_until := -1.0e9
var _chains_used: Dictionary = {}  # chain key -> clock ms when used
var _last_usec := 0
var _det_serial := 0
var _saved_time_scale := 1.0


func _ready() -> void:
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if not auto_process:
		return
	var now := Time.get_ticks_usec()
	var dt_ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	advance(minf(dt_ms, 100.0))


func bind_world(w: DKWorld) -> void:
	w.detonated.connect(on_detonated)
	w.piece_landed.connect(on_piece_landed)
	w.cells_destroyed.connect(on_cells_destroyed)


## Adds shake (0..1). Ignored with reduced motion.
func add_trauma(amount: float) -> void:
	if reduced_motion:
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Requests a hitstop for a chain. Returns true if granted.
func request_hitstop(ms: float, chain_key: Variant) -> bool:
	if reduced_motion or ms <= 0.0:
		return false
	if _chains_used.has(chain_key) or _clock_ms < _cooldown_until:
		return false
	_chains_used[chain_key] = _clock_ms
	var dur := minf(ms, hitstop_max_ms)
	hitstop_left_ms = maxf(hitstop_left_ms, dur)
	_cooldown_until = _clock_ms + dur + hitstop_cooldown_ms
	hitstops_granted += 1
	if use_time_scale:
		if Engine.time_scale > hitstop_time_scale:
			_saved_time_scale = Engine.time_scale
		Engine.time_scale = hitstop_time_scale
	hitstop_started.emit(dur, chain_key)
	return true


func is_in_hitstop() -> bool:
	return hitstop_left_ms > 0.0


## Advances the feel clock by real milliseconds.
func advance(ms: float) -> void:
	_clock_ms += ms
	if hitstop_left_ms > 0.0:
		hitstop_left_ms -= ms
		if hitstop_left_ms <= 0.0:
			hitstop_left_ms = 0.0
			if use_time_scale:
				Engine.time_scale = _saved_time_scale
			hitstop_ended.emit()
	trauma = maxf(0.0, trauma - trauma_decay * ms / 1000.0)
	var amp := 0.0 if reduced_motion else max_offset * trauma * trauma
	# Smooth deterministic wobble (sum of sines on the feel clock).
	var t := _clock_ms / 1000.0
	var o := Vector2(sin(t * 47.0) + 0.5 * sin(t * 83.0 + 1.3), cos(t * 53.0) + 0.5 * sin(t * 71.0 + 0.7)) / 1.5
	offset = (o * amp).round()
	if camera != null:
		camera.offset = offset
	shake_changed.emit(offset)
	# Forget old chain keys (keeps memory flat over a session).
	if _chains_used.size() > 256:
		var keep: Dictionary = {}
		for k in _chains_used:
			if _clock_ms - float(_chains_used[k]) < 10000.0:
				keep[k] = _chains_used[k]
		_chains_used = keep


func set_reduced_motion(on: bool) -> void:
	reduced_motion = on
	if on:
		trauma = 0.0
		offset = Vector2.ZERO
		if camera != null:
			camera.offset = Vector2.ZERO
		if hitstop_left_ms > 0.0:
			advance(hitstop_left_ms)


# — World reactions —

func on_detonated(det: Dictionary, rep: DKReport) -> void:
	var radius := float(det.get("radius", 16.0))
	add_trauma(clampf(radius / 90.0, 0.12, 0.6))
	var key: Variant = det.get("chain", -1)
	if int(key) < 0:
		_det_serial += 1
		key = "det_%d" % _det_serial
	if rep != null and rep.destroyed.size() > 0:
		request_hitstop(hitstop_ms * clampf(radius / 40.0, 0.5, 1.5), key)


func on_cells_destroyed(rep: DKReport) -> void:
	if rep.damage_type != &"crush":
		add_trauma(minf(rep.destroyed.size() / 400.0, 0.15))


func on_piece_landed(piece: Dictionary, _crush: DKDamage, impact: int) -> void:
	var mass := float(piece.get("mass", 1))
	add_trauma(clampf(mass / 600.0 * float(impact) / 256.0, 0.03, 0.45))
