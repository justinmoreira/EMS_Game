# How It Works

This covers the theory behind GEMS's electromagnetic warfare (EW) simulation.

Three unit types share the map:

- **Transceivers** send and receive communication signals to and from other transceivers.
- **Jammers** broadcast noise that drowns out other signals.
- **Sensors** listen for any emission, from transceivers or jammers, and try to detect it.

Every unit has a **transmit power level** (0-10), an **antenna height** (0-10 m of mast above the ground it's standing on), and a **transmit frequency** (30-3000 MHz), plus a **bandwidth** setting (Narrow, Medium, or Wide) that trades reach for how tightly tuned the unit is. Sensors also carry a **sensitivity** and a **tuning frequency** they scan around.

## Signal Propagation

Every link, every jamming check, and every detection uses the same underlying formula for received signal strength:

```
ReceivedPower = (TxPower × HeightFactor × FrequencyFactor) / (DistanceLoss × TerrainLoss)
```

Each term is a knob a player controls, or a condition the map imposes:

- **TxPower** is the transmitter's output (0-10). More power pushes a signal farther and punches through jamming more easily, but power is symmetric: the same wattage that reaches an intended receiver also reaches any enemy sensor listening on a compatible frequency. Cranking power is a range decision and a stealth decision at the same time.
- **HeightFactor** rewards elevation: `1 + (TxHeight + RxHeight) / 1000`, using each side's ground-plus-mast height. This models radio horizons: a taller antenna sees over more terrain before the ground itself gets in the way.
- **FrequencyFactor** is `1000 / Frequency`: lower frequencies carry farther for the same power, at the cost of slower message delivery (see Frequency and Message Speed below).
- **DistanceLoss** is `(distance_km + 1)²`: signal strength falls off with the square of distance. Doubling the distance quarters the signal.
- **TerrainLoss** is the line-of-sight obstruction measurement from the previous section, folded in as a divisor. A clear path costs nothing (a loss of 1); a badly obstructed one can push the denominator high enough to blot out the signal outright.

**ℹ️ Note:** This is a highly simplified model of radio propagation using a linear form of the Free-Space Path Loss formula. It does not account for multipath, diffraction, or other real-world effects, but it is performant and sufficient to model the basic trade-offs of power, height, frequency, and distance in a game context.

A link, or a detection, succeeds only once this whole expression clears a fixed **noise floor** (background noise). Something in the setup has to change, whether that's more power, better elevation, a clearer path, or less distance.

### Frequency and Message Speed

Sending a message over an established link takes time, and that time is set entirely by the frequency in use: delivery scales from 10 seconds at the 30 MHz floor down to a tenth of a second at the 3000 MHz ceiling.

- Low frequency buys range at the cost of a slow link.
- High frequency delivers fast, at shorter range.

VHF/UHF-style high frequencies favor quick, short-hop relays; HF-style low frequencies favor long hops that take longer to carry a message through. A relay chain built from a couple of long, low-frequency hops answers more slowly than one built from several short, high-frequency hops covering the same distance.

### Bandwidth

- **Narrow** bandwidth keeps all of a unit's power concentrated on one exact frequency.
- **Medium** and **Wide** spread that same power across a wider slice of spectrum.

A unit on a narrow channel is efficient but brittle to frequency drift or jamming; a unit on a wide channel is forgiving but weaker per hertz it covers. A link that would clear the noise floor at full power can drop below it once spread across a wider band; that outcome is flagged as a bandwidth penalty.

### Terrain

The battlespace is a 15 km x 15 km stretch of terrain with elevation spanning 0 to 500 m. Anything below the 100 m sea level line renders as water. Terrain values are represented by various colors on the map:

- **White**: Snowy Mountains
- **Tan**: Hills/Plateaus
- **Dark Green**: Valleys
- **Blue**: Rivers/Lakes

The map consists of 150 by 150 grid squares, each 100 m x 100 m. Each square has a single elevation value, and the simulation treats that value as the height of a flat surface across the whole square. The simulation does not model trees, buildings, or other obstacles. This keeps things performant, simple, and easy to understand for those new to the game, while still allowing for a wide variety of terrain shapes and tactical decisions.

Contour lines for the map provide a familiar way to read the terrain for soldiers used to topographic maps. The simulation also provides a terrain heatmap that colors the ground around a unit by how much of that unit's line of sight survives the terrain in each direction. Both are rendered in real time using shaders.

Every unit's height for physics purposes is its **ground elevation plus its own mast**, so a 2 m antenna on a 400 m ridge behaves like a 402 m antenna. Setting a unit down on high ground is a bigger lever on its performance than maxing out the mast slider, because elevation buys two things at once: a taller effective antenna, and a better shot at clearing whatever terrain sits between it and the unit it's trying to reach.

Ridgelines, valleys, and peaks decide which links are possible. Units placed in front of mountains will be unable to link with units behind them. Units in valleys will have a harder time linking with units on ridges.

### Line of Sight and Terrain Masking

The most straightforward way to model terrain is to treat radio signals as straight rays, which is a good approximation for the frequencies in this simulation.

The simulation checks whether the straight path between two antennas clears the terrain in between, but only for units still within each other's theoretical range, as there's no reason to trace a line across the map for a link that power and frequency have already ruled out (received power would be less than the noise floor).

To determine Line-of-Sight:
  - The simulation walks the rasterized straight line, checking the elevation at each point along the line to see if it is higher than the line itself.
  - If any point along the line is higher than the line, then the Terrain Loss factor is increased, which reduces the received power.
  - The more terrain that intrudes into the line of sight, the greater the Terrain Loss factor will be, and the weaker the received signal will be.
  - Once a threshold is reached, the link is considered blocked.

The simulation measures how far into that path the terrain intrudes, not just whether it does. A signal that clips the shoulder of a ridge only loses a little strength. One aimed straight into the middle of a mountain loses all of it, and the link gets marked as blocked, a distinct outcome from a merely weak one. That distinction rewards reading the terrain before committing a unit: a transceiver placed just below a ridge crest can often still talk to the far side, while one dropped in the shadow of the same ridge cannot, even at identical distance and power. The in-game terrain heatmap supports this kind of scouting directly: select a unit and it colors the ground around it by how much of that unit's line of sight, in each direction, survives the terrain.

Units standing on the same spot have no terrain between them, so the line is trivially clear no matter what the map looks like nearby. And two units whose antennas both sit higher than the tallest peak on the map are guaranteed a clear line to each other: a straight line between two points that are each above every obstacle in between them cannot dip low enough to hit one. Get high enough, and terrain stops being a factor at all.

In real life, signal propagation and terrain occlusion are more complex than a simple straight line. Radio signals do not in fact travel as infinitely thin rays, but rather in a sort of ellipsoid shape called the Fresnel Zone. The first Fresnel Zone is the most important one, as it contains the majority of the signal energy. If there is terrain blocking within the first Fresnel Zone, then it can significantly interfere with the signal strength between the two units.

Longer wavelengths, meaning lower frequencies, carve out a fatter zone, so the same hill can matter more to a low-frequency link than a high-frequency one at an identical physical height. The simulation only checks the direct path, not the zone around it, and doesn't factor frequency into the terrain check at all: an obstruction here is either survivable in proportion to how far it intrudes on that one line, or it's a hard block, the same for every frequency. Additionally, even if a unit does not have line of sight to another unit, it may still be able to communicate with it if the signal can diffract around the terrain. However, this simulation does not model diffraction.

## Jamming

A jammer is a transmitter whose payload is noise instead of a message, using the identical received-power formula. For a given receiver, every jammer within range and within its tuning window adds its received power to a running total of interference, weighted by how wide that jammer's own bandwidth is spread. A link survives only if the legitimate signal clears the noise floor by more than that accumulated interference. Terrain, distance, and height affect a jammer's reach the same way they affect a transceiver's.

Jamming is counterable. A jammer's signal degrades under the same conditions any signal does, so the moves that strengthen a weak link also weaken a jammer's hold. Retuning off the jammer's frequency, narrowing bandwidth so its spread power lands weaker, or routing a relay hop behind terrain that blocks the jammer's line of sight all work for the same reason: each is a change to the one formula everything in this simulation runs on.

## Detection

A sensor is the receiver part of a transceiver. It runs the same propagation formula against anything transmitting nearby, transceiver or jammer alike, to determine whether a signal is present at all.

Because the physics are shared, whatever makes a signal easier to receive on purpose also makes it easier to pick up by accident. The power and height choices that extend a transceiver's range are the same choices that make it visible from farther away.

Detection resolves in two tiers:
- A weak signal that clears the noise floor registers as a faint presence.
- A stronger one that clears a sensitivity-scaled threshold counts as a confirmed detection.

Ambient jamming raises that confirmation threshold for an ordinary transmitter, since a sensor has to pick the true transmitter signal out of the noise the jammer itself creates. A jammer, though, is loud by its own definition: its emission is the noise, so it can't hide behind the interference it's generating. A powerful, elevated transceiver reaches farther and jams through more interference, at the cost of being the easiest thing on the board to find.
