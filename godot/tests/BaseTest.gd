extends Node


# Builds a Unit with definition pre-loaded and physical_state populated.
# Works whether or not the test adds it to the scene tree (_ready won't fire
# unless added — but defaults are already in place).
func make_unit(def_id: String, pos: Vector2, overrides: Dictionary = {}) -> Unit:
	var def: UnitDefinition = load("res://data/units/%s.tres" % def_id)
	var unit := Unit.new()
	unit.definition = def
	unit.global_position = pos
	for spec in def.attributes:
		unit.physical_state[spec.id] = spec.default_value
	for k in overrides:
		unit.physical_state[k] = overrides[k]
	return unit


func assert_eq(actual, expected, description := ""):
	if is_equal_approx(actual, expected) if actual is float else actual == expected:
		print("[PASS] ", description)
	else:
		print("[FAIL] ", description, ": Expected ", expected, ", Got ", actual)


func assert_true(condition: bool, description := ""):
	assert_eq(condition, true, description)


func assert_false(condition: bool, description := ""):
	assert_eq(condition, false, description)


func assert_approx(actual: float, expected: float, tolerance: float, description := ""):
	if abs(actual - expected) < tolerance:
		print("[PASS] ", description)
	else:
		print("[FAIL] ", description, ": Expected ~", expected, ", Got ", actual)
