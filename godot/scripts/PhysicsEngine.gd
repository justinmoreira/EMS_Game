extends Node

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0

# Prohibits communication at extreme distance with no power
const NOISE_FLOOR = 0.5

# Different jammer types (bandwidth power)
const BANDWIDTH_POWER = {
	"Narrow": 1.0, # 1 MHz
	"Medium": 0.5, # 10 MHz
	"Wide": 0.3 # 50 MHz
}


func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
	return pos1.distance_to(pos2) / PIXELS_PER_UNIT


func calculate_height_factor(height_tx: float, height_rx: float) -> float:
	return 1.0 + (height_tx + height_rx) / 20.0


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
	rx_frequency: float,
	rx_height: float,
	rx_position: Vector2,
	jammers: Array) -> float:
	"""
	Calculates the total interference power from all jammers.

	Args:
		rx_frequency: Receiver frequency in MHz
		rx_height: Receiver height in meters
		rx_position: Receiver position as Vector2
		jammers: Array of dictionaries with jammer properties:
		{
			"position": Vector2,
			"power": float (0-10),
			"frequency": float (MHz),
			"bandwidth": String ("Narrow", "Medium", "Wide"),
			"height": float (meters)
		}

	Returns:
		Total interference power as a float
	"""
	var total_interference = 0.0
	for jammer in jammers:
		# Check if jammer is within receiver's bandwidth
		var frequency_diff = abs(rx_frequency - jammer.frequency)
		var bandwidth_half = jammer.bandwidth / 2.0

		# Only add interference if frequencies are close enough
		if frequency_diff < bandwidth_half:
			# Calculate jammer's power at receiver (using ReceivedPower formula)
			var jammer_power_at_rx = calculate_received_power(
				jammer.power,
				jammer.height,
				rx_height,
				jammer.frequency,
				calculate_distance(jammer.position, rx_pos),
				1.0 # terrain_loss (assume 1.0 for now)
			)

			# Get bandwidth penalty for this jammer type
			var bandwidth_power = BANDWIDTH_POWER.get(jammer.bandwidth, 1.0)

			# Add to total interference
			total_interference += (jammer_power_at_rx * bandwidth_power)

	return total_interference


func range_check(received_power: float) -> bool:
	"""
	Checks if received power is above noise floor (i.e., in range).

	Args:
		received_power: The calculated received power

	Returns:
		true if in range (signal > noise floor), false if out of range
	"""
	return received_power > NOISE_FLOOR


func jamming_check(received_power: float, interference_power: float) -> bool:
	"""
	Checks if received power overcomes interference and noise floor.

	Args:
		received_power: The calculated received power
		interference_power: Total interference from jammers

	Returns:
		true if link successful (signal beats interference), false if jammed
	"""
	return received_power > (interference_power + NOISE_FLOOR)