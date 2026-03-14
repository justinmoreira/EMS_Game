extends "res://tests/BaseTest.gd"


func _ready():
	test_received_power()


func test_received_power():
	print("Running Received Power Tests...\n")

	# Test 1: Baseline calculation
	# TxPower=10, heights=(5,5), freq=1000, distance=1km, terrain=1
	# HeightFactor = 1 + (5+5)/20 = 1.5
	# FrequencyFactor = 1000/1000 = 1.0
	# DistanceLoss = (1+1)^2 = 4
	# ReceivedPower = (10 * 1.5 * 1.0) / (4 * 1) = 15/4 = 3.75
	var result1 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 1.0, 1.0)
	assert_eq(result1, 3.75, "Baseline calculation: Got 3.75")

	# Test 2: Zero distance (closest possible)
	# DistanceLoss = (0+1)^2 = 1
	# ReceivedPower = (10 * 1.5 * 1.0) / (1 * 1) = 15
	var result2 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 0.0, 1.0)
	assert_eq(result2, 15.0, "Zero distance: Got 15.0")

	# Test 3: Ground level (no height advantage)
	# HeightFactor = 1 + (0+0)/20 = 1.0
	# ReceivedPower = (10 * 1.0 * 1.0) / (4 * 1) = 2.5
	var result3 = PhysicsEngine.calculate_received_power(10.0, 0.0, 0.0, 1000.0, 1.0, 1.0)
	assert_eq(result3, 2.5, "Ground level: Got 2.5")

	# Test 4: Different frequency (higher frequency = lower signal)
	# FrequencyFactor = 1000/2000 = 0.5
	# ReceivedPower = (10 * 1.5 * 0.5) / (4 * 1) = 7.5/4 = 1.875
	var result4 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 2000.0, 1.0, 1.0)
	assert_eq(result4, 1.875, "Higher frequency: Got 1.875")

	# Test 5: Terrain loss attenuation
	# With terrain_loss = 2.0, divides result by 2
	# ReceivedPower = (10 * 1.5 * 1.0) / (4 * 2) = 15/8 = 1.875
	var result5 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 1.0, 2.0)
	assert_eq(result5, 1.875, "Terrain loss: Got 1.875")

	# Test 6: Low transmission power
	# ReceivedPower = (2 * 1.5 * 1.0) / (4 * 1) = 3/4 = 0.75
	var result6 = PhysicsEngine.calculate_received_power(2.0, 5.0, 5.0, 1000.0, 1.0, 1.0)
	assert_eq(result6, 0.75, "Low transmission power: Got 0.75")

	print("\nAll Received Power Tests Complete")
