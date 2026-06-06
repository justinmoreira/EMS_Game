extends "res://tests/BaseTest.gd"


func _ready():
	test_received_power()


func test_received_power():
	print("Running Received Power Tests...\n")

	# Test 1: Baseline calculation
	# TxPower=10, heights=(5,5), freq=1000, distance=1km, terrain=1
	# HeightFactor = 1 + (5+5)/1000 = 1.01
	# FrequencyFactor = 1000/1000 = 1.0
	# DistanceLoss = (1+1)^2 = 4
	# ReceivedPower = (10 * 1.01 * 1.0) / (4 * 1) = 2.525 * GAME_RATIO
	var result1 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 1.0, 1.0)
	assert_eq(
		result1, 2.525 * PhysicsEngine.GAME_CALCULATION_RATIO, "Baseline calculation: Got 3.03"
	)

	# Test 2: Zero distance (closest possible)
	# DistanceLoss = (0+1)^2 = 1
	# ReceivedPower = (10 * 1.01 * 1.0) / (1 * 1) = 10.1 * GAME_RATIO
	var result2 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 0.0, 1.0)
	assert_eq(result2, 10.1 * PhysicsEngine.GAME_CALCULATION_RATIO, "Zero distance: Got 12.12")

	# Test 3: Ground level (no height advantage)
	# HeightFactor = 1 + (0+0)/20 = 1.0
	# ReceivedPower = (10 * 1.0 * 1.0) / (4 * 1) = 2.5 * GAME_RATIO = 7.5
	var result3 = PhysicsEngine.calculate_received_power(10.0, 0.0, 0.0, 1000.0, 1.0, 1.0)
	assert_eq(result3, 2.5 * PhysicsEngine.GAME_CALCULATION_RATIO, "Ground level: Got 7.5")

	# Test 4: Different frequency (higher frequency = lower signal)
	# FrequencyFactor = 1000/2000 = 0.5
	# ReceivedPower = (10 * 1.01 * 0.5) / (4 * 1) = 1.2625 * GAME_RATIO
	var result4 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 2000.0, 1.0, 1.0)
	assert_eq(result4, 1.2625 * PhysicsEngine.GAME_CALCULATION_RATIO, "Higher frequency: Got 1.515")

	# Test 5: Terrain loss attenuation
	# With terrain_loss = 2.0, divides result by 2
	# ReceivedPower = (10 * 1.01 * 1.0) / (4 * 2) = 1.2625 * GAME_RATIO
	var result5 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 1.0, 2.0)
	assert_eq(result5, 1.2625 * PhysicsEngine.GAME_CALCULATION_RATIO, "Terrain loss: Got 1.515")

	# Test 6: Low transmission power
	# ReceivedPower = (2 * 1.01 * 1.0) / (4 * 1) = 0.505 * GAME_RATIO
	var result6 = PhysicsEngine.calculate_received_power(2.0, 5.0, 5.0, 1000.0, 1.0, 1.0)
	assert_eq(
		result6, 0.505 * PhysicsEngine.GAME_CALCULATION_RATIO, "Low transmission power: Got 0.606"
	)

	print("\nAll Received Power Tests Complete")
