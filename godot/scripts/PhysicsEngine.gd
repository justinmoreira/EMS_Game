class_name PhysicsEngine extends RefCounted

enum Bandwidth { BW_NARROW, BW_MED, BW_WIDE }

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0

# Prohibits communication at extreme distance with no power
const NOISE_FLOOR = 0.5

# Parallel arrays indexed by Bandwidth enum (0=Narrow, 1=Medium, 2=Wide).
# Previously these were Dictionary[String, float] with a separate name lookup.
const BANDWIDTH_NAMES := ["Narrow", "Medium", "Wide"]
const BANDWIDTH_POWER := [1.0, 0.5, 0.3]
const BANDWIDTH_MHZ := [1.0, 10.0, 50.0]


static func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
	return pos1.distance_to(pos2) / PIXELS_PER_UNIT


static func calculate_height_factor(height_tx: float, height_rx: float) -> float:
	return 1.0 + (height_tx + height_rx) / 20.0


static func calculate_distance_loss(dis: float) -> float:
	return pow(dis + 1.0, 2.0)


static func bandwidth_penalty(receiver: Bandwidth) -> float:
	match receiver:
		Bandwidth.BW_NARROW:
			return 0.0
		Bandwidth.BW_MED:
			return 2.0
		Bandwidth.BW_WIDE:
			return 5.0
		_:
			return 0.0


static func is_detected(tx: Transceiver, srx: Sensor, dis: float, terrain_loss: float = 1) -> bool:
	var frequency_diff = abs(tx.frequency - srx.tuning_frequency)
	var bandwidth_half = BANDWIDTH_MHZ[srx.sensor_bandwidth] / 2.0

	if frequency_diff > bandwidth_half:
		return false

	var threshold = srx.sensitivity + bandwidth_penalty(srx.sensor_bandwidth)

	var received_power = calculate_received_power(
		tx.power, tx.height, srx.height, tx.frequency, dis, terrain_loss
	)
	return received_power > threshold


static func calculate_received_power(
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


static func calculate_interference(
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
		var frequency_diff = abs(rx_frequency - jammer.frequency)
		var bw_idx: int = jammer.jammer_bandwidth
		var bandwidth_half = BANDWIDTH_MHZ[bw_idx] / 2.0

		if frequency_diff <= bandwidth_half:
			var jammer_power_at_rx = calculate_received_power(
				jammer.power,
				jammer.height,
				rx_height,
				jammer.frequency,
				calculate_distance(jammer.global_position, rx_pos),
				1.0
			)
			total_interference += jammer_power_at_rx * BANDWIDTH_POWER[bw_idx]

	return total_interference


static func range_check(received_power: float) -> bool:
	"""
	Checks if receivedpower is abovenoisefloor

	Args:
		received_power: Thecalculatedreceivedpower

	Returns:
		true if in range(signal > noisefloor), false if outofrange
	"""
	return received_power > NOISE_FLOOR


static func jamming_check(received_power: float, interference_power: float) -> bool:
	"""
	Checks if receivedpowerovercomesinterference and noisefloor

	Args:
		received_power: Thecalculatedreceivedpower
		interference_power: Totalinterferencefromjammers

	Returns:
		true if linksuccessful(signal beatsinterference), false if jammed
	"""
	return received_power > (interference_power + NOISE_FLOOR)


static func bandwidth_penalty_check(received_power: float, penalty: float) -> bool:
	"""
	Checks if receivedpowerovercomesbandwidthpenalty and noisefloor

	Args:
		received_power: Thecalculatedreceivedpower
		penalty: Penaltybasedonreceiverbandwidth

	Returns:
		true if linksuccessful(signal beatsbandwidthpenalty), false if failed due to bandwidth
	"""
	if received_power > (NOISE_FLOOR) && (received_power * penalty) < NOISE_FLOOR:
		return true
	return false
