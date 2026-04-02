# Visual Vision — Energy Flow Like Fluid Through Veins

## The feeling we want

The viewer should FEEL the energy traveling through the body — like blood pumping through veins, like electricity through wires. Not a static colored skeleton. A living, breathing flow.

## How to achieve it

### Animated energy particles
- Small bright dots travel ALONG the bones in the direction of energy flow
- Flow direction: feet → hips → trunk → shoulder → elbow → wrist
- Speed of particles = velocity of that segment
- Slow segments: particles drift lazily (few, dim, slow)
- Fast segments: particles RUSH through (many, bright, fast)
- At release: particles EXPLODE off the wrist into the air

### Glowing veins (bones)
- Bones aren't just colored — they PULSE with brightness
- A wave of brightness travels up the body during the delivery
- Think: neon tubes that light up in sequence
- The wave should be visible even in a still frame

### Node (joint) behavior
- Joints that are accelerating: GROW in size, glow brighter
- Joints that are decelerating: SHRINK, dim
- Peak velocity joint: white-hot core with radiating glow rings
- The "hottest" joint should be immediately obvious

### Color temperature progression
- Ground/feet: cool blue (stable, grounded)
- Hips: warming (energy loading)
- Trunk: orange (rotation building)
- Arm: bright orange-red (acceleration)
- Wrist: WHITE HOT at release (maximum energy)

### Pauses should feel like heartbeats
- At each transition: the action freezes
- The glow PULSES 2-3 times (like a heartbeat)
- A label appears: "TRUNK → ARM: Energy transferring"
- Then resumes — the flow continues

### The overall rhythm
```
[slow build] feet grounded, blue...
[warming] hips start to glow warm...
[PULSE] ← pause, trunk lights up orange
[acceleration] arm swings, bones brighten rapidly
[PULSE] ← pause, arm blazing
[EXPLOSION] wrist goes white-hot, particles fly off
[PULSE] ← pause, "PEAK ENERGY"
[fade] everything cools back to blue as follow-through begins
```

## Technical implementation

### Particles along bones
- For each bone (connection), spawn N particles
- N proportional to velocity of that bone
- Particles travel from proximal joint to distal joint
- Speed proportional to velocity
- Size: 2-4px, with slight blur for glow
- Color: same as the bone's velocity color

### Glow effect on joints
- Base: filled circle at velocity color
- Glow: 3-4 concentric circles with decreasing opacity
- At peak: add radiating lines (like a star/sparkle)

### The wave
- Compute a "wave front" that travels up the body
- Based on the proximal-to-distal peak timing from Gemini
- Joints ahead of the wave: cool/dim
- Joints at the wave: maximum glow
- Joints behind the wave: warm but fading

## What this is NOT
- Not a data dashboard with numbers everywhere
- Not a debug visualization
- Not a medical/clinical scan
- It's a VISUAL EXPERIENCE that tells the story of energy
