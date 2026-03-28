# Data Store Design

## Status

Design note only.
No implementation in this document.

## Core Decision

The Bowling Signature DNA feature should use a **hybrid data architecture**, not a pure vector-database approach.

Recommended direction:
- structured action-signature storage first
- descriptive text chunks second
- vector search as an additional retrieval layer
- hybrid ranking overall

## Why This Is The Right Direction

The feature needs to support two different kinds of similarity.

### 1. Structured action similarity
This is based on:
- phased action parameters
- categorical values
- ordinal bands
- normalized measurable features
- confidence-aware matching

This is the backbone of the system.

### 2. Semantic action similarity
This is based on:
- manual descriptive summaries
- coach-style narratives
- vision-generated action descriptions
- archetype language
- free-text representations of the bowling action

This is where vector search becomes useful.

## Why A Pure Vector Database Is Not Enough

A pure vector-database-first approach is weaker for this feature because the system needs:
- hard filters
- weighted parameter logic
- missingness handling
- explainable match percentages
- coach-readable reasons for the result

These are much easier with structured storage.

## Why A Pure Structured Store Is Also Not Enough Long-Term

A purely structured store can become too rigid when you want to support:
- fuzzy descriptive similarity
- partial free-text retrieval
- narrative coach notes
- vision-generated summaries
- imperfect user-video extraction

That is where embeddings and vector search become useful.

## Recommended Architecture

### Layer 1 — Structured source of truth
Store:
- bowler identity data
- action-signature parameters
- phase-wise values
- confidence fields
- metadata
- clip references
- source provenance

This layer should remain the canonical representation.

### Layer 2 — Descriptive text chunks
Create multiple text representations for each bowler.

Suggested chunk types:
- canonical archetype summary
- phase-by-phase descriptive summary
- coach narrative summary
- visual action summary
- comparison summary

Example:
- “Short accelerating run-up, compact gather, low three-quarter sling release, sharp front-arm pull, compact across-body follow-through, high uniqueness, strong sling archetype.”

### Layer 3 — Vector index
Embed the descriptive chunks and support semantic retrieval.

This is useful when the system has:
- user-generated descriptive text
- vision-generated action descriptions
- partial or fuzzy similarity queries
- coach notes that should retrieve similar archetypes

### Layer 4 — Hybrid ranking
The final result should combine:
- structured parameter score
- vector similarity score
- confidence score

This is better than either approach alone.

## Best Technology Recommendation

### Primary data store
Recommended:
- Postgres

Why:
- strong for structured data
- flexible enough for JSONB payloads
- good for filtering and ranking
- mature and easy to evolve

### Flexible field storage
Recommended:
- JSONB in Postgres

Use for:
- evolving phase-parameter payloads
- confidence maps
- source maps
- pilot schemas

### Vector layer
Recommended later:
- pgvector

Why:
- stays inside Postgres
- simpler operationally
- enough for this use case
- avoids premature dependency on separate vector infrastructure

## Retrieval Strategy

### Phase 1
Use only structured weighted retrieval.

Reason:
- easier to debug
- easier to explain
- best for validating taxonomy quality

### Phase 2
Add descriptive text chunks and vector search.

Reason:
- improves fuzzy similarity
- improves archetype retrieval when structured extraction is sparse
- supports narrative or coach-style queries

### Phase 3
Blend both into hybrid ranking.

Reason:
- stronger match quality
- better usability
- better handling of imperfect inputs

## Example Hybrid Retrieval Flow

1. extract user action parameters from video
2. generate a short descriptive action summary
3. run structured param matching against bowler profiles
4. run vector similarity against descriptive bowler chunks
5. combine both results into final ranking
6. return top matches with:
   - match percentage
   - confidence
   - strongest matching features
   - strongest differentiators

## Important Design Rule

**Career/profile metadata should not dominate the match.**

Fields such as:
- wickets
- rankings
- highest speed
- awards

should mainly be used for:
- display
- context
- coach report enrichment
- optional weak priors

The nearest-archetype result should still be driven mainly by action signature.

## Suggested Descriptive Chunk Types

For each pilot bowler, create several narrative chunks.

### 1. Canonical archetype summary
One short defining description.

### 2. Phase summary
A description of the action across the 7 phases.

### 3. Coach narrative summary
Interpretive version in coaching language.

### 4. Visual style summary
Emphasizes how the action looks to the eye.

### 5. Comparator summary
Explains how this bowler differs from nearby archetypes.

These chunks give the vector layer something meaningful to work with.

## Iterative Improvement Principle

This system should be improved iteratively.

That means:
- structured taxonomy first
- pilot retrieval first
- descriptive chunking second
- embeddings second
- hybrid ranking after the basics work

Do not try to perfect every layer at once.

## Practical Development Sequence

### Stage 1
- define pilot ontology
- store structured bowler profiles
- implement weighted param matching

### Stage 2
- add manual descriptive summaries
- store text chunks
- evaluate whether semantic retrieval adds value

### Stage 3
- generate vision-derived summaries
- add pgvector embeddings
- test hybrid retrieval quality

### Stage 4
- refine blending weights
- add more bowlers
- begin moving from pilot to cluster-scale system

## Final Recommendation

The best long-term design is:
- Postgres as the source of truth
- structured action-signature storage as the backbone
- descriptive text chunking for semantic richness
- pgvector as an optional embedded vector layer
- hybrid retrieval for final nearest-archetype ranking

## Core Rule

**Structured retrieval should provide the discipline; vector retrieval should provide the nuance.**
