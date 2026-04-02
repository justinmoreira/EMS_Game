extends Node

enum Bandwidth { BW_NARROW, BW_MED, BW_WIDE }

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0

# Prohibits communication at extreme distance with no power
const NOISE_FLOOR = 0.5

const BW_LOOKUP = ["Narrow", "Medium", "Wide"]

# Different types of jammers (bandwidth power)
const BANDWIDTH_POWER = {"Narrow": 1.0, "Medium": 0.5, "Wide": 0.3}  # 1 MHz  # 10 MHz  # 50 MHz

# Actual bandwidth values in MHz for each jammer type
const BANDWIDTH_VALUES = {"Narrow": 1.0, "Medium": 10.0, "Wide": 50.0}  # 1 MHz  # 10 MHz  # 50 MHz


func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
	return pos1.distance_to(pos2) / PIXELS_PER_UNIT


func calculate_height_factor(height_tx: float, height_rx: float) -> float:
	return 1.0 + (height_tx + height_rx) / 20.0


func calculate_distance_loss(dis: float) -> float:
	return pow(dis + 1.0, 2.0)


func bandwidth_penalty(receiver: Bandwidth) -> float:
	match receiver:
		Bandwidth.BW_NARROW:
			return 0.0
		Bandwidth.BW_MED:
			return 2.0
		Bandwidth.BW_WIDE:
			return 5.0
		_:
			return 0.0


func is_detected(
	frequency: float,
	receiver: Bandwidth,
	sensitivity: float,
	ptx: float,
	height_tx: float,
	height_sensor: float,
	dis: float,
	terrain_loss: float = 1
) -> bool:
	var threshold = sensitivity + bandwidth_penalty(receiver)

	var srx = calculate_received_power(ptx, height_tx, height_sensor, frequency, dis, terrain_loss)

	return srx > threshold


func calculate_received_power(
	tx_power: float,
	height_tx: float,
	height_rx: float,
	frequency: float,
	distance: float,
	terrain_loss: float = 1.0
) -> float:
	"""
	Calculates the signal strength (received power) between two entities.

	Formula: ReceivedPower = (TxPower * HeightFactor * FrequencyFactor) / (DistanceLoss * TerrainLoss)

	Args:
		tx_power: Transmission power (0-10)
		height_tx: Transmitter height in meters
		height_rx: Receiver height in meters
		frequency: Frequency in MHz (30-3000)
		distance: Distance in km (calculated by calculate_distance)
		terrain_loss: Terrain attenuation factor (default 1.0)

	Returns:
		Signal strength as a float
	"""
	var height_factor = calculate_height_factor(height_tx, height_rx)
	var frequency_factor = 1000.0 / frequency
	var distance_loss = pow(distance + 1.0, 2.0)

	# Avoid division by zero
	if terrain_loss <= 0:
		terrain_loss = 1.0

	var received_power = (
		(tx_power * height_factor * frequency_factor) / (distance_loss * terrain_loss)
	)
	return received_power


func calculate_interference(
	rx_frequency: float, rx_height: float, rx_pos: Vector2, jammers: Array
) -> float:
	"""
	Calculates the total interference power from all jammers

	Args:
		_rx_frequency: Receiverfrequency in MHz
		_rx_height: Receiverheight in meters
		_rx_pos: Receiverposition as Vector2
		jammers: Arrayofdictionarieswithjammerproperties:
		{
			"position": Vector2,
			"power": float(0 - 10),
			"frequency": float(MHz),
			"bandwidth": String("Narrow", "Medium", "Wide"),
			"height": float(meters)
		}

	Returns:
		Totalinterferencepower as a grep -B 2 "var jammer_power_at_rx" godot/scripts/PhysicsEngine.gdfloat
	"""
	var total_interference := 0.0

	for jammer in jammers:
		var jammer_frequency: float
		var jammer_bandwidth
		var jammer_power: float
		var jammer_height: float
		var jammer_position: Vector2

		if jammer is Dictionary:
			jammer_frequency = jammer.get("frequency", 0.0)
			jammer_bandwidth = jammer.get("bandwidth", "Narrow")
			jammer_power = jammer.get("power", 0.0)
			jammer_height = jammer.get("height", 0.0)
			jammer_position = jammer.get("position", Vector2.ZERO)
		else:
			jammer_frequency = jammer.frequency
			jammer_bandwidth = jammer.jammer_bandwidth
			jammer_power = jammer.power
			jammer_height = jammer.height

			if "global_position" in jammer:
				jammer_position = jammer.global_position
			else:
				jammer_position = jammer.position

		var bw_key: String
		if jammer_bandwidth is int:
			if jammer_bandwidth >= 0 and jammer_bandwidth < BW_LOOKUP.size():
				bw_key = BW_LOOKUP[jammer_bandwidth]
			else:
				bw_key = "Narrow"
		else:
			bw_key = str(jammer_bandwidth)

		var frequency_diff = abs(rx_frequency - jammer_frequency)
		var bandwidth_half = BANDWIDTH_VALUES.get(bw_key, 1.0) / 2.0

		if frequency_diff <= bandwidth_half:
			var jammer_power_at_rx = calculate_received_power(
				jammer_power,
				jammer_height,
				rx_height,
				jammer_frequency,
				calculate_distance(jammer_position, rx_pos),
				1.0
			)

			var bandwidth_power = BANDWIDTH_POWER.get(bw_key, 1.0)
			total_interference += jammer_power_at_rx * bandwidth_power

	return total_interference


func range_check(received_power: float) -> bool:
	"""
	Checks if receivedpower is abovenoisefloor

	Args:
		received_power: Thecalculatedreceivedpower

	Returns:
		true if in range(signal > noisefloor), false if outofrange
	"""
	return received_power > NOISE_FLOOR


func jamming_check(received_power: float, interference_power: float) -> bool:
	"""
	Checks if receivedpowerovercomesinterference and noisefloor

	Args:
		received_power: Thecalculatedreceivedpower
		interference_power: Totalinterferencefromjammers

	Returns:
		true if linksuccessful(signal beatsinterference), false if jammed
	"""
	return received_power > (interference_power + NOISE_FLOOR)
