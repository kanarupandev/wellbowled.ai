# WHAT

## What The Feature Is

The Bowling Signature DNA feature is a structured archetype-retrieval system.

It is intended to:
- represent bowlers using phased action signatures
- compare a user action against a reference pool
- retrieve the nearest archetype matches
- return similarity percentages and explanation

It should not be treated as a generic black-box vector search over biography text.

## What The Pilot Should Be

Pilot size:
- 10 prominent seam bowlers

Pilot goal:
- prove that archetype retrieval feels believable
- prove that a user clip can be partially parameterized and matched
- prove that the system can explain why a match was returned

## Recommended Pilot Bowlers

1. Jasprit Bumrah
2. Mitchell Starc
3. Pat Cummins
4. Kagiso Rabada
5. Josh Hazlewood
6. Jofra Archer
7. Shaheen Shah Afridi
8. Mohammed Shami
9. Dale Steyn
10. Lasith Malinga

These bowlers are useful because they provide:
- clear recognition
- high coaching value
- different action families
- useful contrast between classical and unusual actions

## What The System Stores

The system should store multiple layers of information.

### Layer 1: Identity metadata
Used for:
- labeling
- display
- filtering

Examples:
- name
- country
- bowling arm
- bowling style label
- height
- active/retired
- format presence

### Layer 2: Signature profile
Used for:
- primary retrieval
- archetype matching
- explanation

Examples:
- run-up rhythm family
- gather type
- bound type
- shoulder/pelvis orientation family
- front foot alignment family
- release slot family
- follow-through family
- overall action family

### Layer 3: Career/profile context
Used for:
- enrichment
- display
- coach report context

Examples:
- international wickets
- IPL wickets
- rankings
- stock speed band
- highest recorded speed
- best bowling figures

### Layer 4: Reference clip links
Used for:
- annotation
- explainability
- future visual comparison

## What The Primary Match Should Be Based On

The primary match should be based mainly on action-phase signature.

This means:
- what the bowler looks like through the phases
- how the movement is organized
- what family the action belongs to
- how the body positions and transitions behave

It should not be mainly based on:
- wickets
- fame
- current ranking
- raw career profile

## What The Phase Model Should Include

Recommended seam-bowling phase flow:
1. run-up / approach
2. gather / load
3. bound / pre-back-foot-contact
4. back foot contact
5. front foot contact / block phase
6. release
7. follow-through / recovery

These phases are practical because they are both:
- biomechanically meaningful
- visible in video

## What The Parameter Model Should Look Like

Long-term target:
- around 100 parameters
- mostly categorical or ordinal
- a smaller number of normalized quantitative features

Reason:
This is an archetype system, not just a raw coordinate store.

## What Parameter Families Are Needed

### 1. Profile / contextual families
Examples:
- height band
- speed band
- body type band
- dominant formats
- experience/era band

### 2. Phase-action families
Examples:
- run-up rhythm
- gather compactness
- bound type
- alignment family
- front leg family
- front arm family
- release family
- follow-through family

### 3. Higher-order archetype families
Examples:
- sling family
- high-arm family
- compact family
- classical seam family
- hit-through vs whip family
- smooth vs violent action family
- uniqueness family

## What The User Side Should Provide

The user video will not give all 100 parameters equally well.
That is expected.

The system should aim to recover:
- as many reliable primary parameters as possible
- some secondary parameters where confidence is sufficient
- no forced values where evidence is weak

The matching system should then compare only on available, weighted parameters.

## What The Output Should Be

Minimum output:
- top 3 nearest bowler matches
- match percentages
- confidence score
- strongest matching features
- strongest differentiating features
- archetype label or family

Later output:
- coach-facing narrative
- visual comparator
- phase-wise deviation report

## What The Long-Term System Becomes

Long-term target:
- roughly 1000 archetype clusters

Important:
A cluster does not need to have many bowlers.
Some can represent:
- broad action families

Others can represent:
- highly specific rare signatures

That is acceptable.
The point is to map bowling identity, not to force uniform group sizes.

## Final What Statement

The Bowling Signature DNA feature is a phased, parameterized archetype-retrieval system that compares user bowling actions against a reference pool and returns the nearest elite-style matches with explanation.
