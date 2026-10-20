extends DKTest
## Shared demo UI (demos/common, MIT, ships with Lite): the kit's own pixel
## font, the 9-slice/icon atlas, the styled HUD and the callouts, plus their
## use in the Lite demo.


func test_pixel_font_is_complete_and_outlined() -> void:
	var f := DemoPixelFont.new()
	for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?.:-+x·":
		ok(DemoPixelFont.GLYPHS.has(DemoPixelFont.glyph_key(ch)), "glyph for '%s'" % ch)
	ok(f.measure("BOOM") > f.measure("I"), "proportional advance")
	eq(f.measure("boom"), f.measure("BOOM"), "lower case draws as upper case")
	var img := f.atlas_image()
	ok(img != null and img.get_width() > 0, "font atlas built at runtime")


func test_ui_atlas_has_plates_and_icons() -> void:
	var a := DemoUIArt.new()
	for n in [&"panel_pro", &"panel_lite", &"chip_lite", &"badge_lite", &"key", &"bubble", &"bubble_tail"]:
		ok(a.region(n).size.x > 0, "atlas region %s" % n)
	for n in [&"fire", &"barrel", &"chain", &"goon", &"wreck", &"burnt", &"hero", &"falling", &"landed", &"debris", &"star", &"dot"]:
		eq(a.region(StringName("icon_" + String(n))).size, Vector2(11, 11), "icon %s" % n)


func test_callouts_pop_settle_and_do_not_overlap() -> void:
	eq(DemoCallouts.pop_scale(0), 0.4, "pop starts small")
	ok(DemoCallouts.pop_scale(DemoCallouts.POP_IN) > 1.2, "overshoots")
	eq(DemoCallouts.pop_scale(40), 1.0, "settles")
	var c := DemoCallouts.new()
	c.setup(DemoPixelFont.new(), DemoUIArt.new())
	track(c)
	tree().root.add_child(c)
	c.pop("CHAIN x3!", Vector2(200, 200))
	c.pop("CHAIN x3!", Vector2(204, 202))
	c.pop("KA-BOOM!", Vector2(198, 200))
	var rs: Array[Rect2] = []
	for it: Dictionary in c.items:
		rs.append(c._rect(it["text"], it["pos"], float(it["scale"])))
	for i in rs.size():
		for j in range(i + 1, rs.size()):
			ok(not rs[i].intersects(rs[j]), "callouts %d and %d stack instead of overlapping" % [i, j])
	for i in 80:
		c.step()
	eq(c.items.size(), 0, "callouts expire")


func test_lite_demo_uses_styled_hud_and_callouts() -> void:
	var d: Node = load("res://demos/lite_collapse/demo.tscn").instantiate()
	d.manual = true
	tree().root.add_child(d)
	track(d)
	ok(d.hud is DemoHud, "styled HUD (DemoHud)")
	eq(d.hud.style, &"lite", "Lite colour style")
	eq(d.hud.badge, "LITE", "edition badge")
	eq(d.hud.stats.size(), 5, "P1, P2, falling, landed, debris")
	var labels := 0
	for n in d.find_children("*", "Label", true, false):
		labels += 1
	eq(labels, 0, "no plain debug labels left")
	var seen := 0
	for i in 360:
		d.simulate(1)
		for it: Dictionary in d.callouts.items:
			if int(it["t"]) == 1:
				seen += 1
	ok(seen >= 6, "callouts pop on blasts and crashes (%d)" % seen)
	d._update_hud()
	ok(int(d.hud.stats[0]["value"]) > 0, "P1 score shown")
