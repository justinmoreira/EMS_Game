extends "res://tests/BaseTest.gd"


func _ready():
	test_calculate_interference()
	test_range_check()
	test_jamming_check()


func test_calculate_interference():
	print("Running Interference Tests...\n")

	# Test 1: No jammers
	var jammers = []
	var interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	assert_eq(interference, 0.0, "No jammers: Got 0.0")

	# Test 2: Single jammer, same frequency (should interfere)
	# HF = 1 + (5+5)/1000 = 1.01, dist=1km, RP = (5*1.01)/4 * GAME_RATIO = 1.2625 * GAME_RATIO
	# BandwidthPower = 1.0 (Narrow), Total = 1.2625 * GAME_RATIO
	var jammer_a = {
		"power": 5.0,
		"frequency": 1000.0,
		"height": 5.0,
		"jammer_bandwidth": 0,
		"global_position": Vector2(100, 0)
	}
	jammers = [jammer_a]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	assert_eq(
		interference,
		1.2625 * PhysicsEngine.JAMMER_BALANCE_RATIO,
		"Single jammer same frequency: Got 1.515"
	)

	# Test 3: Jammer outside frequency range (should NOT interfere)
	var jammer = {
		"power": 5.0,
		"frequency": 2000.0,
		"height": 5.0,
		"jammer_bandwidth": 0,
		"global_position": Vector2(100, 0)
	}
	jammers = [jammer]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	assert_eq(interference, 0.0, "Jammer outside range: Got 0.0")

	# Test 4: Multiple jammers
	# Jammer1: (5*1.01)/4 * GAME_RATIO * 1.0 = 1.2625 * GAME_RATIO
	# Jammer2: (3*1.01*(1000/1000.5))/4 * GAME_RATIO * 0.5 ≈ 0.3786 * GAME_RATIO
	# Total ≈ 1.6411 * GAME_RATIO
	var jammer1 = {
		"power": 5.0,
		"frequency": 1000.0,
		"height": 5.0,
		"jammer_bandwidth": 0,
		"global_position": Vector2(100, 0)
	}
	var jammer2 = {
		"power": 3.0,
		"frequency": 1000.5,
		"height": 5.0,
		"jammer_bandwidth": 1,
		"global_position": Vector2(100, 0)
	}
	jammers = [jammer1, jammer2]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	assert_approx(
		interference,
		1.6411 * PhysicsEngine.JAMMER_BALANCE_RATIO,
		0.01,
		"Multiple jammers: Got ~1.969"
	)
	print("\n")


func test_range_check():
	print("Running Range Check Tests...\n")
	assert_true(PhysicsEngine.range_check(1.0), "Signal above noise floor: true")
	assert_false(PhysicsEngine.range_check(0.3), "Signal below noise floor: false")
	assert_false(PhysicsEngine.range_check(0.5), "Signal at noise floor: false")
	assert_true(PhysicsEngine.range_check(0.51), "Signal just above noise floor: true")
	print("\n")


func test_jamming_check():
	print("Running Jamming Check Tests...\n")
	assert_true(PhysicsEngine.jamming_check(5.0, 0.0), "Strong signal, no interference: true")
	assert_false(PhysicsEngine.jamming_check(2.0, 2.0), "Signal beaten by interference: false")
	assert_true(PhysicsEngine.jamming_check(3.0, 2.4), "Signal barely beats interference: true")
	assert_false(PhysicsEngine.jamming_check(2.5, 2.0), "Exactly at threshold: false")
	print("\nAll Jamming Tests Complete")
