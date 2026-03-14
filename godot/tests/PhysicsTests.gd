extends "res://tests/BaseTest.gd"


func _ready():
	test_distance()
	test_height()


func test_distance():
	print("Running Distance Tests...")

	# Test 1: Triangle Base: 300, Height:400, Distance should equal 500 / 100 -> 5.0
	var pos1 = Vector2(0, 0)
	var pos2 = Vector2(300, 400)
	var distance1 = PhysicsEngine.calculate_distance(pos1, pos2)
	assert_eq(distance1, 5.0, "Triangle distance: Got 5.0")

	# Test 2: Zero Distance
	var distance2 = PhysicsEngine.calculate_distance(Vector2(10, 10), Vector2(10, 10))
	assert_eq(distance2, 0.0, "Zero Distance: Got 0.0")

	# Test 3: Horizontal Distance
	var distance3 = PhysicsEngine.calculate_distance(Vector2(0, 0), Vector2(100, 0))
	assert_eq(distance3, 1.0, "Horizontal Distance: Got 1.0")

	print("\n")


func test_height():
	print("Running Height Tests")

	# Test 1: Ground Level (0m + 0m)
	var res1 = PhysicsEngine.calculate_height_factor(0.0, 0.0)
	assert_eq(res1, 1.0, "Ground Level: Got 1.0")

	# Test 2: Equal height (10m + 10m)
	var res2 = PhysicsEngine.calculate_height_factor(10.0, 10.0)
	assert_eq(res2, 2.0, "Equal height: Got 2.0")

	# Test 3: Asymmetrical height (20m + 0m)
	var res3 = PhysicsEngine.calculate_height_factor(20.0, 0.0)
	assert_eq(res3, 2.0, "Asymmetrical: Got 2.0")

	print("\n")
