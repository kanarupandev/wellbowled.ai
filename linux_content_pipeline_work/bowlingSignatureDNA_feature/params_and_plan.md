# Parameters And Pilot Plan

## Status

Design note only.
No implementation in this document.

## Core Decision

The system should:
- store a rich canonical profile per bowler
- retrieve using a selective weighted subset
- start with a small pilot pool
- refine weights and active features iteratively

This is the correct design strategy.

## Primary Design Principle

**Store broadly, retrieve selectively.**

This means:
- capture as many useful parameters as possible per bowler
- do not force all parameters to drive every retrieval
- keep retrieval logic flexible
- treat parameter weighting as a separate layer from data storage

This is better than hardcoding one fixed matching scheme too early.

## Why This Approach Is Strong

It separates:
- data capture
from
- retrieval logic

That creates flexibility.

Benefits:
- easier iteration
- easier debugging
- easier experimentation with different matching modes
- better long-term scalability
- no need to redesign the data model when retrieval changes

## What Should Be Stored Per Bowler

Each bowler should have a rich canonical profile containing:
- structured phase parameters
- contextual metadata
- descriptive narrative summaries
- confidence scores
- source references
- clip references where available

This canonical profile becomes the source of truth.

## Parameter Philosophy

The system currently supports a broad taxonomy across:
- context/profile
- run-up / approach
- gather / load
- bound / pre-BFC
- back foot contact
- front foot contact / delivery block
- release
- follow-through / recovery
- higher-order archetype summaries

This gives more than 100 possible fields.

That is acceptable at the storage layer.
It does not mean all 100 should be used equally in retrieval.

## Retrieval Philosophy

Retrieval should be selective.

At retrieval time, the system should decide:
- which parameters are active
- which weights apply
- which filters apply
- which fields are display-only
- how much structured vs semantic similarity contributes

This is the correct place to tune the system.

## Retrieval Classes

### Class A — Primary retrieval fields
Use strongly in matching.
These should mostly be action-signature fields.

Examples:
- release slot family
- arm path family
- run-up rhythm family
- gather compactness
- gather alignment family
- front arm pull family
- front leg technique family
- follow-through direction family
- fallaway family
- overall action family

### Class B — Secondary retrieval fields
Use with lower weight when available.

Examples:
- height band
- stock speed band
- stride length normalized band
- body type band
- release timing band
- block strength family

### Class C — Presentation-only fields
Do not let these dominate nearest-archetype retrieval.
Use for display and context.

Examples:
- international wickets
- IPL wickets
- rankings
- awards
- highest recorded speed
- best bowling figures

## Why Rich Storage Matters

If the system stores broadly, it can later support multiple modes.

### 1. Pure signature mode
Action parameters only.
Useful for strict archetype matching.

### 2. Coach mode
Action parameters plus selected physical/context priors.
Useful for serious reports.

### 3. Consumer mode
Identity-led outputs with stronger narrative framing.

### 4. Hybrid semantic mode
Structured retrieval plus text/vector support.

This flexibility is only possible if the canonical stored profile is rich.

## Pilot Size Recommendation

Start with:
- 10 to 20 bowlers

This is enough for:
- validating the taxonomy
- testing retrieval quality
- checking whether matches feel believable
- finding weak parameters
- improving weighting logic

The first objective is not scale.
It is quality and trust.

## Pilot Bowler Selection Rule

Do not choose only on popularity.
Choose bowlers who are:
- popular
- visually distinct
- archetypally useful
- diverse in action family

The pilot should maximize contrast and recognizability.

## Best Pilot Logic

### Stage 1
Create a canonical signature object for each bowler.

### Stage 2
Populate:
- all structured fields you can support reliably
- narrative summaries
- metadata and source links

### Stage 3
Define a smaller pilot retrieval subset.
Recommended:
- 20 to 30 strongest observable action-signature fields

### Stage 4
Run retrieval experiments.
Adjust:
- weights
- confidence handling
- required filters
- output explanation

### Stage 5
Add more bowlers only after the pilot matches feel believable.

## Long-Term Plan

Long-term, the system can scale toward:
- around 1000 archetype clusters

Interpretation:
- some clusters will contain several bowlers
- some clusters may contain a single highly unique bowler

That is acceptable.
The goal is not uniform cluster size.
The goal is meaningful archetype structure.

## Final Recommendation

The right build strategy is:
1. store rich canonical profiles per bowler
2. start with 10 to 20 bowlers
3. retrieve using a smaller weighted subset
4. refine weights and active params iteratively
5. expand only after the retrieval feels trustworthy

## Core Rule

**Do not optimize the retrieval logic before the canonical bowler profiles are rich enough to support real comparison.**
