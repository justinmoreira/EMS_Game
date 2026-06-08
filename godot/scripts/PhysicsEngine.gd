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

# Increase or decrease to adjust gameplay success
const GAME_CALCULATION_RATIO = 1.2
const SENSOR_BALANCE_RATIO = 3.0


static func calculate_distance(pos1: Vector2, pos2: Vector2) -> float:
	return pos1.distance_to(pos2) / PIXELS_PER_UNIT


static func calculate_height_factor(height_tx: float, height_rx: float) -> float:
	return 1.0 + ((height_tx + height_rx) / (2 * 500.0))


static func calculate_distance_loss(dis: float) -> float:
	return pow(dis + 1.0, 2.0)


static func bandwidth_penalty(receiver: Bandwidth) -> float:
	match receiver:
		Bandwidth.BW_NARROW:
			return 0.0
		Bandwidth.BW_MED:
			return 0.3
		Bandwidth.BW_WIDE:
			return 0.7
		_:
			return 0.0


static func is_detected(tx: Unit, srx: Unit, dis: float, terrain_loss: float = 1) -> bool:
	var frequency_diff = abs(tx.frequency - srx.tuning_frequency)
	var bandwidth_half = BANDWIDTH_MHZ[srx.sensor_bandwidth] / 2.0

	if frequency_diff > bandwidth_half:
		return false

	var threshold = (
		lerpf(3.0, NOISE_FLOOR, srx.sensitivity / 10.0) + bandwidth_penalty(srx.sensor_bandwidth)
	)

	var received_power = calculate_received_power(
		tx.power, tx.height, srx.height, tx.frequency, dis, terrain_loss
	)
	return SENSOR_BALANCE_RATIO * received_power > threshold


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
	# TODO: still not fully FSPL... (no log)
	var height_factor = calculate_height_factor(height_tx, height_rx)
	var frequency_factor = 1000.0 / frequency
	var distance_loss = pow(distance + 1.0, 2.0)

	# Avoid division by zero
	if terrain_loss <= 0:
		terrain_loss = 1.0

	var received_power = (
		(GAME_CALCULATION_RATIO * tx_power * height_factor * frequency_factor)
		/ (distance_loss * terrain_loss)
	)
	return received_power


static func calculate_interference(
	rx_frequency: float,
	rx_total_height: float,
	rx_pos: Vector2,
	jammers: Array,
	height_grid: Array = [],
	map_origin: Vector2 = Vector2(),
	map_scale: Vector2 = Vector2()
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

	var rx_px := rx_pos
	var grid_cols := 0
	var grid_rows := 0
	if height_grid.size() > 0 and map_scale.x != 0 and map_scale.y != 0:
		grid_cols = int(height_grid.size())
		if grid_cols > 0 and height_grid[0] is Array:
			grid_rows = int(height_grid[0].size())

	for jammer in jammers:
		var jam_power: float
		var jam_freq: float
		var bw_idx: int = 0
		var jam_height: float
		var jammer_px: Vector2 = Vector2.ZERO

		jam_power = float(jammer.get("power", 0.0))
		jam_freq = float(jammer.get("frequency", 0.0))
		bw_idx = int(jammer.get("jammer_bandwidth", 0))
		jam_height = float(jammer.get("height", 0.0))
		var terrain_px = jammer.get("terrain_px")
		if terrain_px != null:
			jammer_px = terrain_px
		else:
			var global_pos = jammer.get("global_position")
			if global_pos != null:
				jammer_px = global_pos

		var frequency_diff = abs(rx_frequency - jam_freq)
		var bandwidth_half = BANDWIDTH_MHZ[bw_idx] / 2.0

		if frequency_diff <= bandwidth_half:
			var terrain_loss := 1.0
			var z_jammer := jam_height

			if grid_cols > 0 and grid_rows > 0:
				var rel = jammer_px - map_origin
				var gx = clamp(int(rel.x / map_scale.x), 0, max(0, grid_cols - 1))
				var gy = clamp(int(rel.y / map_scale.y), 0, max(0, grid_rows - 1))
				var ground_h := 0.0
				if gx >= 0 and gx < grid_cols and gy >= 0 and gy < grid_rows:
					ground_h = float(height_grid[gx][gy])

				z_jammer = ground_h + jam_height

				terrain_loss = compute_terrain_loss(
					jammer_px,
					rx_px,
					z_jammer,
					rx_total_height,
					height_grid,
					map_origin,
					map_scale,
				)

			var jammer_power_at_rx = calculate_received_power(
				jam_power,
				z_jammer,
				rx_total_height,
				jam_freq,
				calculate_distance(jammer_px, rx_px),
				terrain_loss
			)
			total_interference += jammer_power_at_rx * BANDWIDTH_POWER[bw_idx]

	return total_interference


static func calculate_signal_range(
	tx_power: float,
	height_tx: float,
	height_rx: float,
	frequency: float,
	target: float = NOISE_FLOOR
) -> float:
	"""
	Calculates the maximum communication range (radius) based on the given parameters, ignoring
	interference and requiring only that the signal is above the noise floor.

	Args:
		tx_power: Transmission power (0-10)
		height_tx: Transmitter height in meters
		height_rx: Receiver height in meters
		frequency: Frequency in MHz (30-3000)
		target: Minimum required received power to be considered "in range" (default is
			NOISE_FLOOR)

	Returns:
		Maximum range in kilometers as a float
	"""
	# Validate inputs
	if frequency <= 0.0 or target <= 0.0:
		return 0.0

	var height_factor = calculate_height_factor(height_tx, height_rx)
	var frequency_factor = 1000.0 / frequency
	var max_distance = (
		sqrt((GAME_CALCULATION_RATIO * tx_power * height_factor * frequency_factor) / target) - 1.0
	)

	return max(0.0, max_distance)
	

static func bresenham(x0: int, y0: int, x1: int, y1: int) -> Array:
	var cells: Array = []
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var step_x: int = 1 if x0 < x1 else -1
	var step_y: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var cx: int = x0
	var cy: int = y0
	while true:
		cells.append(Vector2(cx, cy))
		if cx == x1 and cy == y1:
			break
		var double_error: int = 2 * err  # Don't remove this or refactor it...the entire sim breaks
		if double_error > -dy:
			err -= dy
			cx += step_x
		if double_error < dx:
			err += dx
			cy += step_y
	return cells


static func compute_terrain_loss(
	start_px: Vector2,
	end_px: Vector2,
	z_tx: float,
	z_rx: float,
	height_grid: Array,
	map_origin: Vector2,
	map_scale: Vector2
) -> float:
	# TODO: fresnel zones?
	if height_grid.size() == 0 or map_scale.x == 0 or map_scale.y == 0:
		return 1.0

	var grid_cols := int(height_grid.size())
	var grid_rows := 0
	if grid_cols > 0 and height_grid[0] is Array:
		grid_rows = int(height_grid[0].size())

	var rel_start = start_px - map_origin
	var rel_end = end_px - map_origin
	var grid_x0 = clamp(int(rel_start.x / map_scale.x), 0, grid_cols - 1)
	var grid_y0 = clamp(int(rel_start.y / map_scale.y), 0, grid_rows - 1)
	var grid_x1 = clamp(int(rel_end.x / map_scale.x), 0, grid_cols - 1)
	var grid_y1 = clamp(int(rel_end.y / map_scale.y), 0, grid_rows - 1)

	var path_cells = bresenham(grid_x0, grid_y0, grid_x1, grid_y1)
	var total_dist = calculate_distance(start_px, end_px)
	if total_dist * 1000.0 <= 0.0:
		return 1.0

	# For each sampled cell, compute LOS slope and compare against terrain height
	var sum := 0.0
	for c in path_cells:
		var cx = int(c.x)
		var cy = int(c.y)
		if cx < 0 or cx >= grid_cols or cy < 0 or cy >= grid_rows:
			continue
		var c_ctr = Vector2(
			map_origin.x + (float(cx) + 0.5) * map_scale.x,
			map_origin.y + (float(cy) + 0.5) * map_scale.y
		)
		var projection = clamp(
			(c_ctr - start_px).dot((end_px - start_px).normalized()),
			0.0,
			start_px.distance_to(end_px)
		)
		var d_xy = (projection / PIXELS_PER_UNIT) * 1000.0
		var m = d_xy / (total_dist * 1000.0)
		var z_los = z_tx + (z_rx - z_tx) * m
		var z_terrain = float(height_grid[cx][cy])
		var d = z_terrain - z_los
		if d > 1.0:
			sum += d

	# idk 500 worked best here for some reason
	var tif = 1.0 - clamp(sum / 500.0, 0.0, 1.0)
	return 1.0 / tif  # Inverse for received power calculation


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
