extends "res://tests/BaseTest.gd"


func _ready():
	run_sim_test()

	await get_tree().create_timer(0.1).timeout
	get_tree().quit()


func run_sim_test():
	var engine_root = get_tree().root

	var demo_scene = Node2D.new()
	demo_scene.name = "HeightMapDemo"
	engine_root.add_child.call_deferred(demo_scene)

	await get_tree().process_frame

	var units_folder = Node2D.new()
	units_folder.name = "Units"
	demo_scene.add_child(units_folder)

	var tx_folder = Node2D.new()
	tx_folder.name = "Transceivers"
	units_folder.add_child(tx_folder)

	var jam_folder = Node2D.new()
	jam_folder.name = "Jammers"
	units_folder.add_child(jam_folder)

	var sensor_folder = Node2D.new()
	sensor_folder.name = "Sensors"
	units_folder.add_child(sensor_folder)

	var transceiver1 = Transceiver.new()
	transceiver1.name = "UnitA"
	transceiver1.power = 5
	transceiver1.height = 5
	transceiver1.frequency = 1000.0
	transceiver1.transceiver_bandwidth = 0
	transceiver1.global_position = Vector2(1000, 1000)
	tx_folder.add_child(transceiver1)

	var transceiver2 = Transceiver.new()
	transceiver2.name = "UnitB"
	transceiver2.power = 5
	transceiver2.height = 5
	transceiver2.frequency = 1000.0
	transceiver2.transceiver_bandwidth = 0
	transceiver2.global_position = Vector2(1100, 1000)
	tx_folder.add_child(transceiver2)

	var jammer = Jammer.new()
	jammer.power = 5
	jammer.height = 5
	jammer.frequency = 1000.0
	jammer.jammer_bandwidth = 0
	jammer.global_position = Vector2(1050, 1050)
	jam_folder.add_child(jammer)

	var manager = load("res://scripts/SimulationManager.gd").new()

	engine_root.add_child(manager)

	print("\nStarting SimulationManager Validation...")

	var jammers = [jammer]
	
	var result = manager.calculate_link(transceiver1, transceiver2, jammers)

	assert_true(result == SimulationManager.LinkState.FAILED_JAMMED, "Link correctly identified as JAMMED.")

	jammer.global_position = Vector2(1500, 1500)
	
	var result2 = manager.calculate_link(transceiver1, transceiver2, jammers)

	assert_true(result2 == SimulationManager.LinkState.SUCCESS, "Link correctly identified as CLEAR.")

	manager.queue_free()
	demo_scene.queue_free()
