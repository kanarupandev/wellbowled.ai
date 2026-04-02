# Bowler Database — Complete Field List

## A. PUBLIC DATA (no video needed)

| # | Field | Source | Auto? |
|---|-------|--------|-------|
| 1 | Full name | ESPNcricinfo | Yes |
| 2 | Country | ESPNcricinfo | Yes |
| 3 | Height (cm) | ESPNcricinfo / Wikipedia | Yes |
| 4 | Bowling arm (L/R) | ESPNcricinfo | Yes |
| 5 | Date of birth | ESPNcricinfo | Yes |
| 6 | Playing role | ESPNcricinfo | Yes |
| 7 | Test matches played | ESPNcricinfo | Yes |
| 8 | ODI matches played | ESPNcricinfo | Yes |
| 9 | T20I matches played | ESPNcricinfo | Yes |
| 10 | Test wickets | ESPNcricinfo | Yes |
| 11 | ODI wickets | ESPNcricinfo | Yes |
| 12 | T20I wickets | ESPNcricinfo | Yes |
| 13 | Test bowling average | ESPNcricinfo | Yes |
| 14 | Test strike rate | ESPNcricinfo | Yes |
| 15 | Stock delivery pace (km/h) | Broadcast data / CricViz | Semi |
| 16 | Peak recorded pace (km/h) | Broadcast data | Semi |
| 17 | IPL team(s) | ESPNcricinfo | Yes |
| 18 | Active years (from-to) | ESPNcricinfo | Yes |
| 19 | Bowling style description | ESPNcricinfo | Yes |

**Count: 19 fields. Fully automatable from web scraping.**

---

## B. CRICKET KNOWLEDGE (manual tags, one-time per bowler)

| # | Field | Values | Who fills |
|---|-------|--------|-----------|
| 20 | Pace category | fast / medium-fast / medium / spin | Manual |
| 21 | Action type | side-on / front-on / semi-open / mixed / chest-on | Manual |
| 22 | Arm rotation | over-the-top / high-arm / round-arm / sling | Manual |
| 23 | Primary weapon | pace / swing / seam / bounce / yorker / variation | Manual |
| 24 | Secondary weapon | same options | Manual |
| 25 | Run-up length | long / medium / short | Manual |
| 26 | Run-up speed | fast / moderate / slow | Manual |
| 27 | Follow-through style | aggressive / balanced / minimal | Manual |
| 28 | Known for | e.g., "reverse swing", "death bowling", "new ball" | Manual |
| 29 | Body type | tall-lean / tall-strong / medium / stocky / wiry | Manual |
| 30 | Era/generation | current / recent / classic / legend | Manual |

**Count: 11 fields. 1-2 min per bowler.**

---

## C. GEMINI VISION (1 API call per bowler per clip)

Send clip to Gemini, get qualitative analysis:

| # | Field | What Gemini observes |
|---|-------|---------------------|
| 31 | Run-up rhythm | smooth / choppy / accelerating / decelerating |
| 32 | Gather description | high gather / low gather / no visible gather |
| 33 | Head position at release | behind front foot / over front foot / falling away |
| 34 | Non-bowling arm use | high pull-down / across body / tucked / flailing |
| 35 | Front foot landing | heel first / flat / toe first |
| 36 | Back foot orientation | parallel to crease / angled / pointing down pitch |
| 37 | Follow-through direction | straight down pitch / falling to off / falling to leg |
| 38 | Overall action description | free-form 1-2 sentences |
| 39 | Visual uniqueness | what stands out about this action |
| 40 | Wrist position at release | behind ball / side of ball / on top |

**Count: 10 fields. ~$0.01 per bowler.**

---

## D. SIDE-ON ANGLE MEASUREMENTS (MediaPipe)

The richest source. All angles measured in the 2D side-on projection.

### At BACK FOOT CONTACT (BFC)

| # | Field | Landmarks | What it measures |
|---|-------|-----------|-----------------|
| 41 | Back knee angle | hip-knee-ankle (back leg) | How bent the back knee is at landing |
| 42 | Back hip angle | trunk-hip-knee (back leg) | Hip flexion of back leg |
| 43 | Trunk angle from vertical | shoulder midpoint - hip midpoint vs vertical | Forward lean at BFC |
| 44 | Bowling arm position | shoulder-elbow angle from vertical | Where the arm is during BFC |
| 45 | Head position x | head x relative to back foot x | Head ahead/behind of back foot |
| 46 | Stride start | distance from back ankle to front ankle / torso | Delivery stride beginning |

### At FRONT FOOT CONTACT (FFC)

| # | Field | Landmarks | What it measures |
|---|-------|-----------|-----------------|
| 47 | Front knee angle | hip-knee-ankle (front leg) | Brace stiffness |
| 48 | Front hip angle | trunk-hip-knee (front leg) | Front hip flexion |
| 49 | Back knee angle at FFC | hip-knee-ankle (back leg) | Back leg position at FFC |
| 50 | Hip-shoulder separation | hip line vs shoulder line angle | X-factor / stored rotation |
| 51 | Trunk lateral lean | spine angle from vertical in frontal plane | Side bend |
| 52 | Trunk forward lean | spine angle from vertical in sagittal plane | Forward tilt |
| 53 | Stride length | front ankle to back ankle / torso length | Delivery stride ratio |
| 54 | Bowling arm angle | shoulder-elbow-wrist angle | Arm position at FFC |
| 55 | Non-bowling arm angle | shoulder-elbow-wrist (non-bowling) | Counter-balance position |
| 56 | Head height relative to hip | head y - hip y / torso | Head staying tall or dipping |
| 57 | Front foot position relative to back | x distance / stride | Foot alignment |

### At RELEASE POINT

| # | Field | Landmarks | What it measures |
|---|-------|-----------|-----------------|
| 58 | Front knee angle at release | hip-knee-ankle | Knee brace maintained or collapsed |
| 59 | Hip-shoulder separation at release | hip vs shoulder line | How much rotation used |
| 60 | Bowling arm from vertical | shoulder-wrist angle from vertical | Release height / arm slot |
| 61 | Trunk lean at release | spine from vertical | Upper body position |
| 62 | Bowling wrist height | wrist y / body height | How high the release point is |
| 63 | Head position at release | head x vs front foot x | Falling away or staying tall |
| 64 | Non-bowling arm position | elbow angle | Pulled down or still extended |
| 65 | Front knee change (FFC to release) | angle diff | Knee collapse during delivery |
| 66 | Hip-shoulder change (FFC to release) | angle diff | How much rotation was used between FFC and release |

### At FOLLOW THROUGH

| # | Field | Landmarks | What it measures |
|---|-------|-----------|-----------------|
| 67 | Trunk forward lean | spine angle | How far body goes forward |
| 68 | Bowling arm follow-through | wrist position relative to opposite knee | Completeness of follow-through |
| 69 | Back leg swing | back ankle position relative to body center | Trail leg coming through or not |
| 70 | Body rotation completion | shoulder line relative to pitch direction | Full rotation or incomplete |

### RATIOS AND DERIVED (computed from above)

| # | Field | Derived from |
|---|-------|-------------|
| 71 | Front knee change BFC→FFC | field 47 - field 41 equivalent |
| 72 | Front knee change FFC→release | field 58 - field 47 |
| 73 | Hip-shoulder change FFC→release | field 59 - field 50 |
| 74 | Stride ratio to height | field 53 adjusted by height |
| 75 | Release height ratio | field 62 adjusted by height |
| 76 | Trunk lean change BFC→release | field 61 - field 43 |
| 77 | Action compactness | stride / arm angle / trunk lean composite |

**Count from side-on: 37 fields (41-77)**

---

## E. FRONT-ON ANGLE MEASUREMENTS (MediaPipe)

What side-on CANNOT see that front-on CAN:

| # | Field | What it measures |
|---|-------|-----------------|
| 78 | Shoulder tilt at FFC | Left-right shoulder height difference (3D shoulder alignment) |
| 79 | Hip tilt at FFC | Left-right hip height difference |
| 80 | Chest openness at FFC | How open/closed the chest is to batsman |
| 81 | Front foot alignment | Foot pointing straight / angled / across |
| 82 | Bowling arm plane | Inside / outside the body line |
| 83 | Non-bowling arm symmetry | Mirror position relative to bowling arm |
| 84 | Knee alignment | Knees tracking over toes or collapsing inward |
| 85 | Head alignment | Head tilted / straight / falling to one side |

**Count from front-on: 8 fields (78-85)**

---

## F. BEHIND (BROADCAST) ANGLE MEASUREMENTS (MediaPipe)

The standard TV angle. What it uniquely shows:

| # | Field | What it measures |
|---|-------|-----------------|
| 86 | Run-up line | Straight / angled / curved approach |
| 87 | Run-up width | How wide the approach is relative to crease |
| 88 | Bowling arm visibility | How much of the arm arc is visible from behind |
| 89 | Follow-through direction | Peeling off to left / straight / to right |
| 90 | Back foot landing position | On crease / behind / in front |
| 91 | Front foot landing position | Distance from crease |
| 92 | Stride direction | Straight at batsman / angled across |

**Count from behind: 7 fields (86-92)**

---

## G. MULTI-ANGLE DERIVED (combining 2+ angles)

| # | Field | What it measures | Requires |
|---|-------|-----------------|----------|
| 93 | True 3D hip-shoulder separation | Actual transverse plane angle | Side + front |
| 94 | True arm slot (clock position) | 3D arm angle | Side + front |
| 95 | True stride length | Corrected for camera angle | Side + behind |
| 96 | Action classification score | Composite of multiple metrics | All angles |
| 97 | Injury risk composite | Trunk lean + knee collapse + mixed action flag | Side + front |
| 98 | Efficiency composite | Separation + knee brace + trunk control | Side |
| 99 | Uniqueness score | Distance from centroid of all bowlers | All fields |
| 100 | Style cluster | Which archetype cluster this bowler falls in | All fields |

**Count: 8 fields (93-100)**

---

## SUMMARY

| Category | Fields | Source | Auto? |
|----------|--------|-------|-------|
| A. Public data | 19 | Web scraping | Yes |
| B. Cricket knowledge | 11 | Manual tags | No (1-2 min/bowler) |
| C. Gemini vision | 10 | API call | Yes ($0.01/bowler) |
| D. Side-on angles | 37 | MediaPipe | Yes (needs SAM 2 first) |
| E. Front-on angles | 8 | MediaPipe | Yes (needs front-on clip) |
| F. Behind angles | 7 | MediaPipe | Yes (needs behind clip) |
| G. Multi-angle derived | 8 | Computed | Yes (if multiple angles available) |
| **TOTAL** | **100** | | |

## WHAT WE CAN FILL WITH SIDE-ON ONLY

Categories A + B + C + D = **77 fields** from side-on clip + public data + manual tags + Gemini.

That's enough for meaningful matching with 1000 bowlers.

## WHAT 3 ANGLES ADDS

Categories E + F + G = **23 more fields** from front-on and behind clips.

Nice to have. Not essential for MVP. Add later when DB is established.

## AUTOMATION LEVEL FOR 1000 BOWLERS (SIDE-ON ONLY)

| Step | Per bowler | 1000 bowlers | Can batch? |
|------|-----------|-------------|------------|
| Find side-on clip | 2 min | 33 hours | Partially (search scripts) |
| SAM 2 extract (Mac MPS) | 5 min | 83 hours | Yes (batch script) |
| MediaPipe angles (auto) | 10 sec | 3 hours | Yes (fully auto) |
| Gemini qualitative | 30 sec | 8 hours | Yes (batch API) |
| Public data scrape | 5 sec | 1.5 hours | Yes (fully auto) |
| Manual cricket tags | 1 min | 17 hours | No |
| **Total** | **~9 min** | **~145 hours** | |

With parallelization and tooling: realistically **60-80 hours** for 1000 bowlers.
