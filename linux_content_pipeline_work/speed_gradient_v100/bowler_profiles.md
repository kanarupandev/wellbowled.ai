# Bowler Profiles — Calibration Data

## Known bowlers

| Bowler | Height | Stock Pace | Peak Pace | Arm | Action |
|--------|--------|-----------|-----------|-----|--------|
| Dale Steyn | 179 cm | ~150 km/h | 156.7 km/h | Right | Side-on |
| Jasprit Bumrah | 178 cm | ~145 km/h | 153.3 km/h | Right | Unique (hyperextended) |
| Brett Lee | 190 cm | ~155 km/h | 161.1 km/h | Right | Front-on |
| Glenn McGrath | 196 cm | ~135 km/h | 150.6 km/h | Right | Side-on |
| James Anderson | 188 cm | ~135 km/h | 142.5 km/h | Right | Side-on (swing) |

## Calibration approach

1. Measure torso-length in frame (mid-shoulder to mid-hip in pixels)
2. Known torso ≈ 47% of height → real torso length in cm
3. pixel_to_cm = real_torso_cm / pixel_torso_length
4. velocity_cm_per_s = pixel_velocity × pixel_to_cm × fps
5. Convert to km/h for meaningful comparison

## Normalization for cross-clip comparison

For clips from SIMILAR camera angles:
- Body-size normalization (torso-lengths/s) handles camera distance
- Height calibration converts to real-world m/s
- Known ball speed validates the calibration

For clips from DIFFERENT camera angles:
- Only transfer RATIOS are comparable (not absolute velocities)
- The ratio between consecutive segments cancels out angle effects
