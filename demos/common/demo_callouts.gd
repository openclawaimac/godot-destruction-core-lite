class_name DemoCallouts
extends Node2D
## Floating comic callouts ("CHAIN x7!", "KA-BOOM!") and speech bubbles in
## the demos' pixel font: pixel outline, two-tone fill, a pop (scale up past
## full size, settle) on appear, a slow rise and a fade. Tick-driven (`step`)
## so headless runs stay deterministic; drawing reads the state only.

const POP_IN := 5
const SETTLE := 10

var font: DemoPixelFont
var art: DemoUIArt
## Live callouts: {text, pos, t, life, scale, fill, fill_b, rise}.
var items: Array = []
var max_items := 8


func setup(p_font: DemoPixelFont, p_art: DemoUIArt) -> void:
	font = p_font
	art = p_art


## Pop scale for an item `age` ticks old: 0.4 -> 1.3 -> 1.0.
static func pop_scale(age: int) -> float:
	if age < POP_IN:
		return 0.4 + 0.9 * float(age) / POP_IN
	if age < SETTLE:
		return 1.3 - 0.3 * float(age - POP_IN) / (SETTLE - POP_IN)
	return 1.0


func pop(text: String, pos: Vector2, scale := 2.0, fill := Color("ffe066"), fill_b := Color("ff8a2b"), life := 70) -> void:
	if items.size() >= max_items:
		items.pop_front()
	# Stack above live callouts instead of overlapping them.
	if font != null:
		for _try in 8:
			var r := _rect(text, pos, scale)
			var hit := false
			for it: Dictionary in items:
				var o := _rect(it["text"], it["pos"], float(it["scale"]))
				if r.grow(2).intersects(o):
					pos.y = o.position.y - r.size.y / 2.0 - 4.0
					hit = true
					break
			if not hit:
				break
	items.append({"text": text, "pos": pos, "t": 0, "life": life, "scale": scale,
		"fill": fill, "fill_b": fill_b, "rise": 0.35})


## Settled on-screen box of a callout (centred on `pos`).
func _rect(text: String, pos: Vector2, scale: float) -> Rect2:
	var sz := Vector2(font.measure(text) * scale, DemoPixelFont.H * scale)
	return Rect2(pos - sz / 2.0, sz)


func step() -> void:
	var keep: Array = []
	for it: Dictionary in items:
		it["t"] = int(it["t"]) + 1
		it["pos"] = (it["pos"] as Vector2) + Vector2(0, -float(it["rise"]) if int(it["t"]) > SETTLE else 0.0)
		if int(it["t"]) < int(it["life"]):
			keep.append(it)
	items = keep
	queue_redraw()


func _draw() -> void:
	if font == null:
		return
	for it: Dictionary in items:
		var t := int(it["t"])
		var life := int(it["life"])
		var a := clampf(float(life - t) / 15.0, 0.0, 1.0)
		var s := pop_scale(t)
		var base: float = it["scale"]
		var text: String = it["text"]
		var w := font.measure(text) * base
		var h := DemoPixelFont.H * base
		var p: Vector2 = (it["pos"] as Vector2).round()
		draw_set_transform(p, 0.0, Vector2(s, s))
		var fill: Color = it["fill"]
		var fill_b: Color = it["fill_b"]
		font.draw(self, Vector2(-roundf(w / 2.0), -roundf(h / 2.0)), text, base, Color(fill, a),
			Color(DemoUIArt.INK, a), Color(fill_b, a), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A shouted line ("HOT HOT HOT!") over a character, tail tip at `tip`, in
## the same comic style as the callouts: pixel font at 2x, two-tone fill
## (`fill` -> `accent`), ink outline and drop shadow, popping in over its first
## ticks (`age`) with a small panic jitter and a pointer down to the speaker.
## No plate behind it, so it reads as part of the action, not as UI text.
## Drawn on any canvas item (the demos' fx layers).
static func draw_bubble(ci: CanvasItem, f: DemoPixelFont, _a: DemoUIArt, tip: Vector2, text: String, age: int,
		accent := Color("ff5a2b"), fill := Color("fff1c4"), scale := 2.0) -> void:
	var s := pop_scale(age)
	var w := float(f.measure(text)) * scale
	var h := DemoPixelFont.H * scale
	var jitter := Vector2(float((age / 3) % 3 - 1), 0.0) if age >= SETTLE else Vector2.ZERO
	ci.draw_set_transform(tip.round() + jitter, 0.0, Vector2(s, s))
	# Pointer: a small inked wedge from the text down to the speaker.
	var ink := DemoUIArt.INK
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-4, -6), Vector2(4, -6), Vector2(0, 0)]), ink)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-2, -6), Vector2(2, -6), Vector2(0, -2)]), accent)
	f.draw(ci, Vector2(-roundf(w / 2.0), -h - 7.0), text, scale, fill, ink, accent, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
