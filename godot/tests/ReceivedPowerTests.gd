extends Node


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
	if is_equal_approx(result1, 3.75):
		print("[PASS] Baseline calculation: Got 3.75")
	else:
		print("[FAIL] Baseline calculation: Expected 3.75, Got ", result1)

	# Test 2: Zero distance (closest possible)
	# DistanceLoss = (0+1)^2 = 1
	# ReceivedPower = (10 * 1.5 * 1.0) / (1 * 1) = 15
	var result2 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 0.0, 1.0)
	if is_equal_approx(result2, 15.0):
		print("[PASS] Zero distance: Got 15.0")
	else:
		print("[FAIL] Zero distance: Expected 15.0, Got ", result2)

	# Test 3: Ground level (no height advantage)
	# HeightFactor = 1 + (0+0)/20 = 1.0
	# ReceivedPower = (10 * 1.0 * 1.0) / (4 * 1) = 2.5
	var result3 = PhysicsEngine.calculate_received_power(10.0, 0.0, 0.0, 1000.0, 1.0, 1.0)
	if is_equal_approx(result3, 2.5):
		print("[PASS] Ground level: Got 2.5")
	else:
		print("[FAIL] Ground level: Expected 2.5, Got ", result3)

	# Test 4: Different frequency (higher frequency = lower signal)
	# FrequencyFactor = 1000/2000 = 0.5
	# ReceivedPower = (10 * 1.5 * 0.5) / (4 * 1) = 7.5/4 = 1.875
	var result4 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 2000.0, 1.0, 1.0)
	if is_equal_approx(result4, 1.875):
		print("[PASS] Higher frequency: Got 1.875")
	else:
		print("[FAIL] Higher frequency: Expected 1.875, Got ", result4)

	# Test 5: Terrain loss attenuation
	# With terrain_loss = 2.0, divides result by 2
	# ReceivedPower = (10 * 1.5 * 1.0) / (4 * 2) = 15/8 = 1.875
	var result5 = PhysicsEngine.calculate_received_power(10.0, 5.0, 5.0, 1000.0, 1.0, 2.0)
	if is_equal_approx(result5, 1.875):
		print("[PASS] Terrain loss: Got 1.875")
	else:
		print("[FAIL] Terrain loss: Expected 1.875, Got ", result5)

	# Test 6: Low transmission power
	# ReceivedPower = (2 * 1.5 * 1.0) / (4 * 1) = 3/4 = 0.75
	var result6 = PhysicsEngine.calculate_received_power(2.0, 5.0, 5.0, 1000.0, 1.0, 1.0)
	if is_equal_approx(result6, 0.75):
		print("[PASS] Low transmission power: Got 0.75")
	else:
		print("[FAIL] Low transmission power: Expected 0.75, Got ", result6)

	print("\nAll Received Power Tests Complete")
