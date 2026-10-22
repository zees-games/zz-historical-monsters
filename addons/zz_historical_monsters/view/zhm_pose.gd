extends RefCounted

## What a monster's body does for each thing it can be doing, as bone rotations.
##
## [b]The base models were static meshes, so every clip is code.[/b] A pose is a [Dictionary] of
## bone name to [Vector3] of (pitch, yaw, roll) in degrees, each in the MODEL's own axes: +pitch
## swings the bone's far end up and toward the front for a bone that points forward (a head up) and
## foot forward for one that hangs (a leg), +yaw turns it to the left, +roll tips it over to its left.
## [ZhmView] turns each into a local rotation. Two keys are not bones: [code]_root[/code] tips the
## whole body, and [code]_lift[/code] raises or lowers it (x metres, as a fraction of the body's
## height) and [code]_lunge[/code] shifts it forward (x) as a fraction of its length.
##
## [b]No assertion reaches a pose.[/b] Look at one with [code]tools/screenshot.sh[/code].

## What a monster looks like it is doing. Replicated by a host as one small integer; a client
## chooses a clip by it and nothing on the server reads it back. Appended, never inserted.
enum Anim {
	IDLE, WALK, RUN, BITE, ROAR, SWEEP, CHARGE_WIND, CHARGE, STAGGER, STALK, POUNCE_WIND, LEAP,
	MAUL, SLAM_WIND, SLAM, DEAD, LAND,
}


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in Anim.keys():
		out.append(String(k).to_lower())
	return out


## Radians of gait phase per metre walked, per species: a T-Rex's stride is long.
static func stride(species: StringName) -> float:
	match species:
		&"trex":
			return 0.62
		&"tiger":
			return 1.9
		_:
			return 1.5


## The pose of [param species] doing [param anim], [param t] seconds into it, with the gait at
## [param phase] radians and moving at [param speed] m/s. [param variant] picks a side of a combo.
static func pose(species: StringName, anim: int, t: float, phase: float, speed: float, variant: int) -> Dictionary:
	var p: Dictionary = {}

	match species:
		&"trex":
			_trex(p, anim, t, phase, speed)
		&"tiger":
			_cat(p, anim, t, phase, speed, variant)
		&"bear":
			_bear(p, anim, t, phase, speed, variant)

	if anim == Anim.DEAD:
		# Falls over onto its side and twitches once; the view does the rest of the fall.
		var fall := clampf(t / 0.9, 0.0, 1.0)
		p[&"_root"] = Vector3(0.0, 0.0, 88.0 * fall * fall * (3.0 - 2.0 * fall))
		p[&"_lift"] = -0.06 * fall

	return p


static func _add(p: Dictionary, bone: StringName, pitch: float, yaw: float = 0.0, roll: float = 0.0) -> void:
	# Several clips add to one bone (a gait and a lunge), so a second call sums.
	var cur: Vector3 = p.get(bone, Vector3.ZERO)
	p[bone] = cur + Vector3(pitch, yaw, roll)


static func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Mostly-sinusoidal twitch that is never still: an infected body is never at rest.
static func _twitch(t: float, seed_: float) -> float:
	return sin(t * 13.0 + seed_) * sin(t * 7.3 + seed_ * 2.1)


# --- T-Rex: biped, a long tail, tiny arms ---------------------------------------------------

static func _trex(p: Dictionary, anim: int, t: float, ph: float, speed: float) -> void:
	var run := clampf(speed / 9.0, 0.0, 1.0)
	var walk := clampf(speed / 3.0, 0.0, 1.0)
	var amp := 1.0
	var s := sin(ph)
	var c := cos(ph)

	# A breathing, twitching idle under everything.
	_add(p, &"head", _twitch(t, 1.0) * 2.5, _twitch(t, 4.0) * 5.0)
	_add(p, &"jaw", -3.0 - 2.0 * sin(t * 2.2))
	_add(p, &"tail1", 0.0, sin(t * 0.9) * 6.0)
	_add(p, &"tail2", 0.0, sin(t * 0.9 - 0.8) * 8.0)
	_add(p, &"tail3", 0.0, sin(t * 0.9 - 1.6) * 10.0)
	_add(p, &"armL", 20.0 + _twitch(t, 7.0) * 18.0)
	_add(p, &"armR", 20.0 + _twitch(t, 9.0) * 18.0)

	var gait := walk * (1.0 - 0.0)
	if anim in [Anim.WALK, Anim.RUN, Anim.CHARGE, Anim.STALK]:
		amp = lerpf(0.8, 1.35, run)
		_add(p, &"legL_up", s * 26.0 * amp * gait)
		_add(p, &"legR_up", -s * 26.0 * amp * gait)
		_add(p, &"legL_lo", -(0.5 + 0.5 * sin(ph + 1.0)) * 34.0 * gait)
		_add(p, &"legR_lo", -(0.5 + 0.5 * sin(ph + 1.0 + PI)) * 34.0 * gait)
		_add(p, &"legL_ft", (0.5 + 0.5 * sin(ph + 1.0)) * 24.0 * gait)
		_add(p, &"legR_ft", (0.5 + 0.5 * sin(ph + 1.0 + PI)) * 24.0 * gait)
		_add(p, &"pelvis", 0.0, 0.0, s * 4.0 * gait)
		_add(p, &"spine", 0.0, -s * 3.0 * gait, 0.0)
		_add(p, &"head", -c * 3.0 * gait, -s * 5.0 * gait)
		_add(p, &"tail1", 0.0, -s * 9.0 * gait)
		_add(p, &"tail2", 0.0, -s * 11.0 * gait)
		_add(p, &"tail3", 0.0, -s * 12.0 * gait)
		p[&"_lift"] = p.get(&"_lift", 0.0) + absf(c) * 0.012 * gait

	match anim:
		Anim.BITE:
			# A snap: head draws back, drives forward and down, the jaw gapes, and snaps shut.
			var back := _ease(t / 0.28)
			var drive := _ease((t - 0.28) / 0.12)
			var shut := _ease((t - 0.42) / 0.12)
			_add(p, &"neck", 14.0 * back - 52.0 * drive + 30.0 * shut)
			_add(p, &"head", 10.0 * back - 18.0 * drive + 8.0 * shut)
			_add(p, &"jaw", -(50.0 * (back + drive) - 52.0 * shut) * 0.8)
			_add(p, &"spine", 4.0 * back - 14.0 * drive + 8.0 * shut)
			p[&"_lunge"] = 0.07 * drive * (1.0 - shut)
		Anim.ROAR:
			var up := _ease(t / 0.45)
			var shake := sin(t * 55.0) * 2.2
			_add(p, &"spine", 16.0 * up)
			_add(p, &"neck", 28.0 * up)
			_add(p, &"head", 26.0 * up + shake, shake * 1.4)
			_add(p, &"jaw", -58.0 * up)
			_add(p, &"armL", 40.0 * up, 14.0 * up)
			_add(p, &"armR", 40.0 * up, -14.0 * up)
			_add(p, &"tail2", 0.0, shake * 2.0)
			p[&"_root"] = Vector3(8.0 * up, 0.0, 0.0)
		Anim.SWEEP:
			# Body wound round to the left, the tail whipped far past it. The body's yaw is the
			# brain's; this is only the whip.
			var w := _ease(t / 0.35)
			_add(p, &"spine", 0.0, 25.0 * w)
			_add(p, &"pelvis", 0.0, 10.0 * w)
			_add(p, &"tail1", 0.0, -34.0 * w)
			_add(p, &"tail2", 0.0, -42.0 * w)
			_add(p, &"tail3", 0.0, -48.0 * w)
			_add(p, &"head", 0.0, 12.0 * w)
		Anim.CHARGE_WIND:
			var d := _ease(t / 0.5)
			_add(p, &"neck", -22.0 * d)
			_add(p, &"head", -14.0 * d + _twitch(t * 3.0, 2.0) * 2.0)
			_add(p, &"jaw", -14.0 * d)
			_add(p, &"spine", -9.0 * d)
			# The right foot rakes the ground.
			var rake := sin(t * 11.0) * 0.5 + 0.5
			_add(p, &"legR_up", 24.0 * d * rake)
			_add(p, &"legR_lo", -30.0 * d * rake)
			p[&"_lift"] = -0.03 * d
		Anim.CHARGE:
			_add(p, &"neck", -24.0)
			_add(p, &"head", -12.0)
			_add(p, &"jaw", -30.0 - 8.0 * sin(t * 18.0))
			_add(p, &"spine", -10.0)
			p[&"_root"] = Vector3(-5.0, 0.0, 0.0)
		Anim.STAGGER:
			var k := sin(t * 14.0) * exp(-t * 1.6)
			_add(p, &"neck", -20.0 + 14.0 * k)
			_add(p, &"head", -14.0, 24.0 * k)
			_add(p, &"jaw", -24.0 + 6.0 * k)
			_add(p, &"spine", -6.0, 8.0 * k)
			p[&"_lift"] = -0.02


# --- Tiger: a four-legged cat ---------------------------------------------------------------

static func _quad_legs(p: Dictionary, ph: float, amp: float, bend: float, gait: float, front: bool) -> void:
	# Diagonal pairs: front left with back right.
	var offsets := {
		&"armL": 0.0, &"legR": 0.0, &"armR": PI, &"legL": PI,
	}
	for key in offsets.keys():
		var o: float = offsets[key]
		var sw := sin(ph + o)
		var up := StringName(String(key) + "_up")
		var lo := StringName(String(key) + "_lo")
		var ft := StringName(String(key) + "_ft")
		_add(p, up, sw * amp * gait)
		_add(p, lo, -(0.5 + 0.5 * sin(ph + o + 1.1)) * bend * gait)
		_add(p, ft, (0.5 + 0.5 * sin(ph + o + 1.1)) * bend * 0.5 * gait)


static func _cat(p: Dictionary, anim: int, t: float, ph: float, speed: float, variant: int) -> void:
	var run := clampf(speed / 9.0, 0.0, 1.0)
	var walk := clampf(speed / 1.6, 0.0, 1.0)
	var s := sin(ph)

	_add(p, &"head", _twitch(t, 2.0) * 3.0, _twitch(t, 5.0) * 7.0)
	_add(p, &"jaw", -6.0 - 4.0 * sin(t * 3.1))
	_add(p, &"tail1", 0.0, sin(t * 1.6) * 10.0)
	_add(p, &"tail2", 0.0, sin(t * 1.6 - 1.0) * 16.0)
	_add(p, &"tail3", 0.0, sin(t * 1.6 - 2.0) * 24.0)
	_add(p, &"spine", 0.0, _twitch(t, 3.0) * 2.0)

	if anim in [Anim.WALK, Anim.RUN, Anim.STALK, Anim.CHARGE]:
		var amp := lerpf(22.0, 42.0, run)
		_quad_legs(p, ph, amp, lerpf(30.0, 55.0, run), walk, true)
		# A gallop folds and unfolds the spine.
		_add(p, &"spine", sin(ph * 1.0 + 0.6) * lerpf(2.0, 8.0, run) * walk)
		_add(p, &"pelvis", -sin(ph + 0.6) * lerpf(1.0, 6.0, run) * walk)
		_add(p, &"tail1", 0.0, -s * 8.0 * walk)
		p[&"_lift"] = absf(s) * lerpf(0.01, 0.03, run) * walk

	match anim:
		Anim.STALK:
			# Low to the ground, shoulders working, head down between them.
			_add(p, &"neck", -18.0)
			_add(p, &"head", -10.0)
			_add(p, &"spine", 6.0)
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, -20.0)
			for b in [&"legL_up", &"legR_up"]:
				_add(p, b, 30.0)
			p[&"_lift"] = p.get(&"_lift", 0.0) - 0.16
		Anim.BITE:
			var back := _ease(t / 0.2)
			var drive := _ease((t - 0.2) / 0.1)
			var shut := _ease((t - 0.34) / 0.1)
			_add(p, &"neck", 12.0 * back - 40.0 * drive + 22.0 * shut)
			_add(p, &"head", 8.0 * back - 20.0 * drive)
			_add(p, &"jaw", -(58.0 * (back + drive)) * (1.0 - shut) * 0.8)
			_add(p, &"spine", -6.0 * drive)
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, 24.0 * drive * (1.0 - shut))
			p[&"_lunge"] = 0.08 * drive * (1.0 - shut)
		Anim.ROAR:
			var u := _ease(t / 0.3)
			_add(p, &"neck", 18.0 * u)
			_add(p, &"head", 14.0 * u, sin(t * 50.0) * 3.0)
			_add(p, &"jaw", -62.0 * u)
		Anim.POUNCE_WIND:
			var d := _ease(t / 0.5)
			p[&"_lift"] = -0.24 * d
			_add(p, &"spine", 16.0 * d)
			_add(p, &"neck", -22.0 * d)
			_add(p, &"head", -8.0 * d)
			for b in [&"legL_up", &"legR_up"]:
				_add(p, b, 45.0 * d)
			for b in [&"legL_lo", &"legR_lo"]:
				_add(p, b, -50.0 * d)
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, -30.0 * d)
			_add(p, &"tail1", 0.0, sin(t * 17.0) * 18.0 * d)
			_add(p, &"tail3", 0.0, sin(t * 17.0 - 1.0) * 36.0 * d)
		Anim.LEAP:
			# Stretched out: forelegs reaching, hind legs trailing, jaw wide.
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, 62.0)
			for b in [&"armL_lo", &"armR_lo"]:
				_add(p, b, 16.0)
			for b in [&"legL_up", &"legR_up"]:
				_add(p, b, -52.0)
			for b in [&"legL_lo", &"legR_lo"]:
				_add(p, b, -8.0)
			_add(p, &"spine", -10.0)
			_add(p, &"neck", -8.0)
			_add(p, &"jaw", -64.0)
		Anim.LAND:
			var d2 := 1.0 - _ease(t / 0.4)
			p[&"_lift"] = -0.2 * d2
			_add(p, &"spine", 10.0 * d2)
			_add(p, &"jaw", -40.0 * d2)
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, 30.0 * d2)
		Anim.STAGGER:
			var k := sin(t * 15.0) * exp(-t * 1.8)
			_add(p, &"neck", -16.0)
			_add(p, &"head", -10.0, 28.0 * k)
			p[&"_lift"] = -0.05


# --- Bear: heavy, rears up --------------------------------------------------------------------

static func _bear(p: Dictionary, anim: int, t: float, ph: float, speed: float, variant: int) -> void:
	var run := clampf(speed / 7.0, 0.0, 1.0)
	var walk := clampf(speed / 1.6, 0.0, 1.0)
	var s := sin(ph)

	_add(p, &"head", _twitch(t, 3.0) * 4.0, _twitch(t, 6.0) * 9.0)
	_add(p, &"jaw", -8.0 - 5.0 * sin(t * 2.6))
	_add(p, &"spine", 0.0, _twitch(t, 8.0) * 2.0)

	if anim in [Anim.WALK, Anim.RUN, Anim.CHARGE]:
		var amp := lerpf(20.0, 36.0, run)
		for key in [&"armL", &"legR"]:
			_add(p, StringName(String(key) + "_up"), sin(ph) * amp * walk)
			_add(p, StringName(String(key) + "_lo"), -(0.5 + 0.5 * sin(ph + 1.1)) * 30.0 * walk)
		for key in [&"armR", &"legL"]:
			_add(p, StringName(String(key) + "_up"), sin(ph + PI) * amp * walk)
			_add(p, StringName(String(key) + "_lo"), -(0.5 + 0.5 * sin(ph + 1.1 + PI)) * 30.0 * walk)
		# The lumbering roll of a heavy animal: shoulders and rump swing opposite ways.
		_add(p, &"spine", 0.0, -s * 4.0 * walk, s * 3.0 * walk)
		_add(p, &"pelvis", 0.0, s * 4.0 * walk)
		_add(p, &"head", 0.0, s * 6.0 * walk)
		p[&"_lift"] = absf(cos(ph)) * 0.015 * walk

	match anim:
		Anim.BITE:
			var back := _ease(t / 0.3)
			var drive := _ease((t - 0.3) / 0.12)
			var shut := _ease((t - 0.46) / 0.12)
			_add(p, &"neck", 14.0 * back - 44.0 * drive + 24.0 * shut)
			_add(p, &"head", 8.0 * back - 16.0 * drive)
			_add(p, &"jaw", -(54.0 * (back + drive)) * (1.0 - shut) * 0.8)
			p[&"_lunge"] = 0.07 * drive * (1.0 - shut)
		Anim.ROAR:
			var u := _ease(t / 0.4)
			p[&"_root"] = Vector3(20.0 * u, 0.0, 0.0)
			_add(p, &"neck", 14.0 * u)
			_add(p, &"head", 18.0 * u, sin(t * 48.0) * 3.0)
			_add(p, &"jaw", -60.0 * u)
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, 60.0 * u)
		Anim.MAUL:
			# A swipe from one arm: raised and across, then torn down; the other arm on odd hits.
			var side := &"armL_up" if variant % 2 == 0 else &"armR_up"
			var lo_side := &"armL_lo" if variant % 2 == 0 else &"armR_lo"
			var sgn := 1.0 if variant % 2 == 0 else -1.0
			var raise := _ease(t / 0.28)
			var rake := _ease((t - 0.28) / 0.1)
			var rec := _ease((t - 0.45) / 0.2)
			_add(p, side, (95.0 * raise - 150.0 * rake + 55.0 * rec), 30.0 * sgn * rake)
			_add(p, lo_side, 25.0 * raise - 40.0 * rake + 15.0 * rec)
			_add(p, &"spine", 0.0, -22.0 * sgn * rake + 22.0 * sgn * rec, 0.0)
			_add(p, &"neck", -10.0 * rake)
			_add(p, &"jaw", -30.0 * raise)
			p[&"_lunge"] = 0.05 * rake * (1.0 - rec)
			p[&"_root"] = Vector3(8.0 * raise * (1.0 - rec), 0.0, 0.0)
		Anim.SLAM_WIND:
			var u2 := _ease(t / 0.8)
			p[&"_root"] = Vector3(44.0 * u2, 0.0, 0.0)
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, 150.0 * u2)
			for b in [&"armL_lo", &"armR_lo"]:
				_add(p, b, 25.0 * u2)
			_add(p, &"neck", 20.0 * u2)
			_add(p, &"head", 14.0 * u2)
			_add(p, &"jaw", -64.0 * u2)
			p[&"_lift"] = 0.05 * u2
		Anim.SLAM:
			var d := _ease(t / 0.12)
			var rec2 := _ease((t - 0.35) / 0.4)
			p[&"_root"] = Vector3(44.0 * (1.0 - d) * 0.0 + (-14.0 * d + 14.0 * rec2), 0.0, 0.0)
			for b in [&"armL_up", &"armR_up"]:
				_add(p, b, 150.0 * (1.0 - d) - 10.0 * d + 10.0 * rec2)
			_add(p, &"neck", -30.0 * d * (1.0 - rec2))
			_add(p, &"jaw", -50.0 * (1.0 - rec2))
			p[&"_lift"] = -0.04 * d * (1.0 - rec2)
		Anim.STAGGER:
			var k := sin(t * 13.0) * exp(-t * 1.6)
			_add(p, &"neck", -18.0)
			_add(p, &"head", -12.0, 26.0 * k)
			_add(p, &"spine", 0.0, 6.0 * k)
			p[&"_lift"] = -0.03
