extends Node

# This will map to 100 pixels -> 1 km
const PIXELS_PER_UNIT = 100.0


func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
    return pos1.distance_to(pos2) / PIXELS_PER_UNIT


func calculate_height_factor(height_tx: float, height_rx: float) -> float:
    return 1.0 + (height_tx + height_rx) / 20.0

func calculate_received_power(tx_power: float, height_tx: float, height_rx: float, 
								frequency: float, distance: float, terrain_loss: float = 1.0) -> float:
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
	
	var received_power = (tx_power * height_factor * frequency_factor) / (distance_loss * terrain_loss)
	return received_power