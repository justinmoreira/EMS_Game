extends "res://tests/BaseTest.gd"


func _ready():
	test_bresenham()
	test_compute_terrain_loss()


func test_bresenham():
	print("Running Bresenham Tests...\n")

	# Single point: path of length 0 contains just the start cell
	var r1 = PhysicsEngine.bresenham(2, 3, 2, 3)
	assert_true(r1.size() == 1 and r1[0] == Vector2(2, 3), "Single point: one cell at (2,3)")

	# Horizontal right: visits every column exactly once
	assert_true(
		(
			PhysicsEngine.bresenham(0, 0, 3, 0)
			== [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0)]
		),
		"Horizontal right: 4 cells"
	)

	# Horizontal left: same cells in reverse order
	assert_true(
		(
			PhysicsEngine.bresenham(3, 0, 0, 0)
			== [Vector2(3, 0), Vector2(2, 0), Vector2(1, 0), Vector2(0, 0)]
		),
		"Horizontal left: 4 cells reversed"
	)

	# Vertical down
	assert_true(
		(
			PhysicsEngine.bresenham(0, 0, 0, 3)
			== [Vector2(0, 0), Vector2(0, 1), Vector2(0, 2), Vector2(0, 3)]
		),
		"Vertical down: 4 cells"
	)

	# 45-degree diagonal: one cell per step
	assert_true(
		PhysicsEngine.bresenham(0, 0, 2, 2) == [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
		"Diagonal: 3 cells"
	)

	# Non-square slope: verifies interpolation doesn't skip cells
	var r6 = PhysicsEngine.bresenham(0, 0, 4, 2)
	assert_true(
		r6.size() == 5 and r6[0] == Vector2(0, 0) and r6[4] == Vector2(4, 2),
		"4x2 slope: 5 cells, correct endpoints"
	)

	print("\n")


func test_compute_terrain_loss():
	print("Running Terrain Loss Tests...\n")

	# Empty grid: no height data, no loss
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(0, 0), Vector2(100, 0), 10.0, 10.0, [], Vector2.ZERO, Vector2(100, 100)
		),
		1.0,
		"Empty grid: loss = 1.0"
	)

	# Zero-scale map: no loss
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(0, 0), Vector2(100, 0), 10.0, 10.0, [[10.0]], Vector2.ZERO, Vector2.ZERO
		),
		1.0,
		"Zero map scale: loss = 1.0"
	)

	# Zero distance (start = end): no loss
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(50, 50), Vector2(50, 50), 10.0, 10.0, [[10.0]], Vector2.ZERO, Vector2(100, 100)
		),
		1.0,
		"Zero distance: loss = 1.0"
	)

	# Terrain (5 m) is below LOS (10 m) everywhere -> d < 1 at every cell
	# 1x1 grid, single midpoint: z_los = 10, z_terrain = 5, d = -5, loss = 1.0
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(0, 0), Vector2(100, 0), 10.0, 10.0, [[5.0]], Vector2.ZERO, Vector2(100, 100)
		),
		1.0,
		"Terrain below LOS: loss = 1.0"
	)

	# 3x1 flat terrain at 0 m, antennas at 10 m: all cells clear
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(0, 0),
			Vector2(300, 0),
			10.0,
			10.0,
			[[0.0], [0.0], [0.0]],
			Vector2.ZERO,
			Vector2(100, 100)
		),
		1.0,
		"Flat terrain, clear LOS: loss = 1.0"
	)

	# 3x1 grid, middle column at 110 m, antennas at 10 m
	# Middle cell: m = 0.5, z_los = 10, z_terrain = 110, d = 100
	# sum = 100, tif = 1 - 100/500 = 0.8, loss = 1/0.8 = 1.25
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(0, 0),
			Vector2(300, 0),
			10.0,
			10.0,
			[[0.0], [110.0], [0.0]],
			Vector2.ZERO,
			Vector2(100, 100)
		),
		1.25,
		"Partial obstruction (d=100): loss = 1.25"
	)

	# 1x1 grid at 260 m, antennas at 10 m
	# d = 250, sum = 250, tif = 0.5, loss = 1/0.5 = 2.0
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(0, 0), Vector2(100, 0), 10.0, 10.0, [[260.0]], Vector2.ZERO, Vector2(100, 100)
		),
		2.0,
		"Heavy obstruction (d=250): loss = 2.0"
	)

	# Same 3x1 grid with the 110 m middle column, but antennas at 500 m
	# z_los at midpoint = 500, z_terrain = 110, d = -390, no contribution
	assert_eq(
		PhysicsEngine.compute_terrain_loss(
			Vector2(0, 0),
			Vector2(300, 0),
			500.0,
			500.0,
			[[0.0], [110.0], [0.0]],
			Vector2.ZERO,
			Vector2(100, 100)
		),
		1.0,
		"Elevated antennas clear obstacle: loss = 1.0"
	)

	# 1x1 grid at 510 m, antennas at 10 m.
	# d = 500, sum = 500, clamp, tif = 0, loss = 1/0 = INF
	var total_block = PhysicsEngine.compute_terrain_loss(
		Vector2(0, 0), Vector2(100, 0), 10.0, 10.0, [[510.0]], Vector2.ZERO, Vector2(100, 100)
	)
	assert_true(is_inf(total_block), "Total blockage (d=500): loss = INF")

	print("\nAll Terrain Loss Tests Complete\n")
