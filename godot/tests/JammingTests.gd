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
	var jammer_a = make_unit(
		"jammer",
		Vector2(100, 0),
		{"frequency": 1000.0, "power": 5, "height": 5, "jammer_bandwidth": 0}
	)
	jammers = [jammer_a]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	# JammerPowerAtRx = calculate_received_power(5, 5, 5, 1000, 1, 1) = 1.875 * GAME_RATIO = 5.625
	# BandwidthPower = 1.0 (Narrow)
	# Total = 5.625 * 1.0 = 5.625
	assert_eq(
		interference,
		1.875 * PhysicsEngine.GAME_CALCULATION_RATIO,
		"Single jammer same frequency: Got 5.625"
	)

	jammer_a.free()

	# Test 3: Jammer outside frequency range (should NOT interfere)
	var jammer = make_unit(
		"jammer",
		Vector2(100, 0),
		{"frequency": 2000.0, "power": 5, "height": 5, "jammer_bandwidth": 0}
	)
	jammers = [jammer]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	assert_eq(interference, 0.0, "Jammer outside range: Got 0.0")
	jammer.free()

	# Test 4: Multiple jammers
	var jammer1 = make_unit(
		"jammer",
		Vector2(100, 0),
		{"frequency": 1000.0, "power": 5, "height": 5, "jammer_bandwidth": 0}
	)
	var jammer2 = make_unit(
		"jammer",
		Vector2(100, 0),
		{"frequency": 1000.5, "power": 3, "height": 5, "jammer_bandwidth": 1}
	)
	jammers = [jammer1, jammer2]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)

	# Jammer 1: 1.875 * 1.0 = 1.875
	# Jammer 2: calculate_received_power(3, 5, 5, 1000.5, 1, 1) ≈ 2.25 * 0.5 = 1.125
	# Total ≈ 2.437 * GAME_RATIO ~ 7.311
	assert_approx(
		interference,
		2.437 * PhysicsEngine.GAME_CALCULATION_RATIO,
		0.01,
		"Multiple jammers: Got ~7.311"
	)

	jammer1.free()
	jammer2.free()
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
