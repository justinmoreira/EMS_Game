extends "res://tests/BaseTest.gd"


func _ready() -> void:
	test_sensor_detection()


func test_sensor_detection():
	print("\nRunning Sensor Detection Tests...")

	var engine_root = get_tree().root

	var demo_scene = Node2D.new()
	demo_scene.name = "HeightMapDemo"
	engine_root.add_child.call_deferred(demo_scene)

	await get_tree().process_frame

	var units_folder = Node2D.new()
	units_folder.name = "Units"
	demo_scene.add_child(units_folder)

	var transceiver1 = make_unit(
		"transceiver",
		Vector2(1000, 1000),
		{"power": 5, "height": 5, "frequency": 500.0, "transceiver_bandwidth": 0}
	)
	transceiver1.name = "UnitA"
	units_folder.add_child(transceiver1)

	var transceiver2 = make_unit(
		"transceiver",
		Vector2(1500, 1000),
		{"power": 5, "height": 5, "frequency": 500.0, "transceiver_bandwidth": 0}
	)
	transceiver2.name = "UnitB"
	units_folder.add_child(transceiver2)

	var sensor = make_unit(
		"sensor",
		Vector2(1100, 1000),
		{"sensitivity": 3, "height": 5, "tuning_frequency": 500, "sensor_bandwidth": 0}
	)
	units_folder.add_child(sensor)

	var manager = load("res://scripts/SimulationManager.gd").new()
	engine_root.add_child(manager)

	print("\n")

	var detected = manager.calculate_detection(sensor, transceiver1)
	assert_true(detected, "Detection success case.")

	var detected2 = manager.calculate_detection(sensor, transceiver2)
	assert_false(detected2, "Detection fail case.")

	sensor.set_value(&"sensitivity", 8)
	var detected3 = manager.calculate_detection(sensor, transceiver1)
	assert_false(detected3, "Detection fail case.")

	print("\n")

	manager.queue_free()
	demo_scene.queue_free()
