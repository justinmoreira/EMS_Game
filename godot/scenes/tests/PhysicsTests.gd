extends Node

func _ready():
	test_distance()
	test_height()
	
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
	
func test_distance():
	print("Running Distance Tests...")
	
	# Test 1: Triangle Base: 300, Height:400, Distance should equal 500 / 100 -> 5.0
	var pos1 = Vector2(0,0)
	var pos2 = Vector2(300,400)
	var distance1 = PhysicsEngine.calculate_distance(pos1, pos2)
	
	if is_equal_approx(distance1, 5.0):
		print("[PASS] Got 5.0")
	else:
		print("[FAIL] Expected 5.0, Got ", distance1)
		
	# Test 2: Zero Distance
	var distance2 = PhysicsEngine.calculate_distance(Vector2(10, 10), Vector2(10, 10))
	if distance2 == 0.0:
		print("[PASS] Zero Distance: Got 0.0")
	else:
		print("[FAIL] Zero Distance: Got ", distance2)

	# Test 3: Horizontal Distance
	var distance3 = PhysicsEngine.calculate_distance(Vector2(0, 0), Vector2(100, 0))
	if distance3 == 1.0:
		print("[PASS] Horizontal Distance: Got 1.0")
	else:
		print("[FAIL] Horizontal Distance: Got ", distance3)
	
	print("\n")

func test_height():
	print("Running Height Tests")
	
	# Test 1: Ground Level (0m + 0m) 
	var res1 = PhysicsEngine.calculate_height_factor(0.0, 0.0)
	if is_equal_approx(res1, 1.0):
		print("[PASS] Ground Level: Got 1.0")
	else:
		print("[FAIL] Ground Level: Expected 1.0, Got ", res1)

	# Test 2: Equal height (10m + 10m)
	var res2 = PhysicsEngine.calculate_height_factor(10.0, 10.0)
	if is_equal_approx(res2, 2.0):
		print("[PASS] Got 2.0")
	else:
		print("[FAIL] Expected 2.0, Got ", res2)

	# Test 3: Asymmetrical height (20m + 0m)
	var res3 = PhysicsEngine.calculate_height_factor(20.0, 0.0)
	if is_equal_approx(res3, 2.0):
		print("[PASS] Asymmetrical: Got 2.0")
	else:
		print("[FAIL] Asymmetrical: Expected 2.0, Got ", res3)
	
	print("\n")
	
