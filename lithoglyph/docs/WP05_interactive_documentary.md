# White Paper 05: Lith for Interactive Documentary and Journalism

**Status**: Draft  
**Version**: 0.1.0  
**Date**: 2025-01-11  
**Authors**: Jonathan D.A. Jewell, Claude (Anthropic)  
**License**: MPL-2.0

## Abstract

Interactive documentary (i-doc) represents a paradigm shift from linear narrative to reader-driven navigation through evidence. However, i-docs lack appropriate database infrastructure—traditional databases cannot track the provenance, corrections, and multi-perspective navigation that journalism requires. This white paper presents Lith as purpose-built infrastructure for i-docs, demonstrating how narrative-first database design enables epistemological transparency, audience-specific navigation (boundary objects), and correction workflows essential for journalism in the post-truth era.

## 1. Introduction

### 1.1 The i-doc Movement

Interactive documentary emerged in the 2010s as a response to passive media consumption. As defined by MIT's Open Doc Lab (Aston & Gaudenzi, 2012):

> **i-doc**: "Any project that starts with an intention to document the 'real' and that uses digital interactive technology to realize this intention."

Key principles:
- **Navigation over narration**: Readers choose their own path through evidence
- **Multiple entry points**: Different audiences access the same evidence differently
- **Transparency**: Epistemological foundations are visible, not hidden
- **Living documents**: Content updates, corrections, retractions over time

**Examples**:
- *Hollow* (Elaine McMillion Sheldon): Multi-perspective rural documentary
- *Fort McMoney* (David Dufresne): Interactive journalism game
- *Gaza/Sderot* (Bruno + Arte): Dual-perspective conflict coverage

### 1.2 The Database Problem

i-docs require databases that can:

1. **Track evidence provenance**: "Where did this claim come from?"
2. **Support corrections transparently**: Retractions, updates, clarifications
3. **Enable multi-perspective navigation**: Same evidence, different audience paths
4. **Maintain epistemological metadata**: Quality scores, verification status
5. **Preserve narrative context**: Why was this evidence included? By whom? When?

**Traditional databases fail** because they:
- Treat history as write-only audit logs (not queryable narrative)
- Lack semantic distinction between data changes and corrections
- Cannot represent "why" a connection exists between evidence and claims
- Require application-level code for provenance tracking

### 1.3 Lith as i-doc Infrastructure

Lith was designed for exactly this use case:

| i-doc Requirement | Lith Feature |
|-------------------|----------------|
| Evidence provenance | `[PROVENANCE]` queries, journal entries |
| Transparent corrections | Reversible operations with rationale |
| Multi-perspective navigation | Boundary object collections (navigation paths) |
| Epistemological metadata | PROMPT scores as first-class data |
| Narrative context | Constraints-as-ethics, explainable operations |

**Thesis**: Lith is the natural database for i-docs because it treats the database itself as part of the documentary story.

## 2. i-doc Theory: Navigation Over Narration

### 2.1 Reader Agency

Traditional journalism:
```
Journalist → Article → Reader (passive)
```

i-doc:
```
Journalist → Evidence Graph → Reader (active navigator)
```

**Example** (UK Inflation 2023):

Traditional article:
> "Inflation in 2023 disproportionately affected renters, with rent costs rising 12% compared to 8% overall inflation, according to ONS data."

i-doc approach:
- **Claim**: "Inflation disproportionately affected renters"
- **Evidence**: ONS CPI data, academic study, think tank report
- **Relationships**: Which evidence supports/contradicts/contextualizes?
- **Navigation paths**: 
  - Skeptic → Start with methodology
  - Policymaker → Start with authoritative sources
  - Affected person → Start with personal impact stories

Readers choose their path based on their needs.

### 2.2 Boundary Objects (Star & Griesemer, 1989)

**Definition**: Objects that inhabit multiple social worlds and satisfy the informational requirements of each.

In i-docs, **the same evidence serves multiple audiences**:

| Evidence | Researcher Perspective | Policymaker Perspective | Affected Person Perspective |
|----------|------------------------|-------------------------|------------------------------|
| ONS CPI Data | Methodology → Replicability → Raw data | Authority → Summary stats → Recommendations | "What does this mean for me?" → Rent specifically |
| Academic Study | Peer review status → Citations → Methods | Policy implications → Summary | Readability → Plain language |
| Expert Interview | Credentials → Bias disclosure → Full transcript | Authority → Key quotes | Relatability → Human story |

Lith enables this via **navigation path collections** (Section 4).

### 2.3 Epistemological Transparency

i-docs must make their epistemology **visible and queryable**:

**Bad** (opaque):
> "Sources confirm inflation affected renters more."

**Good** (transparent):
> "This claim is supported by:
> - ONS CPI data (PROMPT score: 97.5/100, provenance: 100, replicability: 100)
> - Academic study (PROMPT: 81.8, peer-reviewed, n=5000 households)
> - Think tank report (PROMPT: 72.3, methodology transparent but non-peer-reviewed)
> 
> Counterpoint from landlords' association (PROMPT: 59, expert interview, not replicated)"

Lith makes this queryable:
```gql
-- Get all evidence supporting a claim, sorted by PROMPT overall score
SELECT evidence.title, evidence.prompt_overall, 
       relationship.weight, relationship.reasoning
FROM claims 
  JOIN relationships ON claims.id = relationships.from_id
  JOIN evidence ON relationships.to_id = evidence.id
WHERE claims.id = 'claim_renters_disproportionate'
ORDER BY evidence.prompt_overall DESC;
```

## 3. The PROMPT Framework in Lith

### 3.1 PROMPT Dimensions

PROMPT (Provenance, Replicability, Objective, Methodology, Publication, Transparency) is a 6-dimensional framework for scoring evidence quality (Wineburg et al., 2022).

Lith stores PROMPT scores as **narrative metadata**:

```gql
CREATE COLLECTION evidence (
  id UUID PRIMARY KEY,
  title VARCHAR NOT NULL,
  evidence_type VARCHAR NOT NULL,
  prompt_scores STRUCT {
    provenance INT,        -- 0-100: Source authority/chain of custody
    replicability INT,     -- 0-100: Reproducibility of findings
    objective INT,         -- 0-100: Bias/conflicts of interest
    methodology INT,       -- 0-100: Research quality/rigor
    publication INT,       -- 0-100: Peer review/editorial standards
    transparency INT,      -- 0-100: Data/methods availability
    overall COMPUTED AS AVG(all above)
  },
  added_by VARCHAR,
  added_at TIMESTAMP,
  url TEXT,
  zotero_key VARCHAR
) WITH RATIONALE;
```

**Example** (from BoFIG UK Inflation dataset):

| Evidence | Prov | Repl | Obj | Meth | Pub | Trans | Overall |
|----------|------|------|-----|------|-----|-------|---------|
| ONS CPI Data | 100 | 100 | 95 | 95 | 100 | 95 | 97.5 |
| Academic Study (peer-reviewed) | 85 | 80 | 75 | 85 | 90 | 75 | 81.8 |
| Think Tank Report | 75 | 70 | 65 | 75 | 80 | 70 | 72.3 |
| Expert Interview | 85 | 45 | 60 | 50 | 40 | 75 | 59.0 |

### 3.2 PROMPT Score Evolution

Scores change over time (retractions, replication failures):

```gql
-- Initial scoring
INSERT INTO evidence (title, prompt_scores) 
VALUES ('Climate Study X', {
  provenance: 90,
  replicability: 85,
  objective: 80,
  methodology: 90,
  publication: 95,
  transparency: 85
})
SCORED_BY "journalist_jane"
RATIONALE "Peer-reviewed in Nature, strong methodology, data available";

-- Later: Replication failure
UPDATE evidence 
SET prompt_scores.replicability = 30,
    prompt_scores.overall = RECOMPUTE
WHERE id = 'climate_study_x'
REASON "Study failed to replicate per Science retraction notice 2024-03-15"
RETRACTION_URL "https://doi.org/10.1126/science.retraction.2024.03"
DISCLOSED_BY "editor_bob"
DISCLOSED_AT "2024-03-16T09:00:00Z";

-- Lith journals this as a correction, preserving original scores in provenance
```

**Agents/readers can query score history**:
```gql
INTROSPECT evidence.climate_study_x PROMPT_HISTORY;

-- Returns:
-- [
--   { date: "2024-01-15", overall: 87.5, scored_by: "jane", 
--     note: "Initial scoring" },
--   { date: "2024-03-16", overall: 67.5, scored_by: "bob",
--     note: "Replication failure", replicability: 85→30 }
-- ]
```

### 3.3 Audience-Weighted PROMPT

Different audiences prioritize different dimensions:

| Audience | Top Priority | Secondary | Tertiary |
|----------|--------------|-----------|----------|
| Researcher | Methodology, Replicability | Transparency | Publication |
| Policymaker | Provenance, Publication | Objective | Methodology |
| Skeptic | Objective, Transparency | Replicability | Provenance |
| Affected Person | Transparency, Objective | Provenance | (simplicity) |

Lith supports audience-specific scoring:
```gql
SELECT evidence.title,
       audience_weighted_prompt(evidence.prompt_scores, 'RESEARCHER') AS researcher_score,
       audience_weighted_prompt(evidence.prompt_scores, 'SKEPTIC') AS skeptic_score
FROM evidence
WHERE investigation = 'uk_inflation_2023';

-- Custom weighting function:
CREATE FUNCTION audience_weighted_prompt(scores, audience) AS
  CASE audience
    WHEN 'RESEARCHER' THEN 
      0.30 * scores.methodology + 0.30 * scores.replicability + 
      0.20 * scores.transparency + 0.20 * scores.publication
    WHEN 'SKEPTIC' THEN
      0.35 * scores.objective + 0.30 * scores.transparency + 
      0.20 * scores.replicability + 0.15 * scores.provenance
    -- ... etc
  END;
```

## 4. Boundary Objects: Navigation Paths

### 4.1 Implementation in Lith

```gql
CREATE COLLECTION navigation_paths (
  id UUID PRIMARY KEY,
  name VARCHAR NOT NULL,
  investigation_id VARCHAR NOT NULL,
  audience_type ENUM('RESEARCHER', 'POLICYMAKER', 'SKEPTIC', 'AFFECTED_PERSON') NOT NULL,
  description TEXT,
  created_by VARCHAR,
  created_at TIMESTAMP
) WITH RATIONALE;

CREATE COLLECTION path_nodes (
  path_id UUID REFERENCES navigation_paths(id),
  entity_id UUID NOT NULL,  -- claim_id or evidence_id
  entity_type ENUM('CLAIM', 'EVIDENCE') NOT NULL,
  order INT NOT NULL,
  context TEXT,  -- Why this node is in this position for this audience
  PRIMARY KEY (path_id, order)
);
```

### 4.2 Example: UK Inflation 2023

**Researcher Path**:
```gql
CREATE NAVIGATION_PATH 'researcher_path_inflation'
FOR INVESTIGATION 'uk_inflation_2023'
AUDIENCE 'RESEARCHER'
BEGIN
  -- Start with methodology
  NODE evidence WHERE evidence_type = 'methodology' 
    CONTEXT "Researchers want to evaluate methods first"
    ORDER 1;
  
  -- Then primary data
  NODE evidence WHERE prompt_provenance = 100 
    CONTEXT "Official statistics (ONS) have highest provenance"
    ORDER 2;
  
  -- Then peer-reviewed studies
  NODE evidence WHERE prompt_publication >= 90
    CONTEXT "Academic validation matters to researchers"
    ORDER 3;
  
  -- Then claims
  NODE claims WHERE confidence_level >= 0.85
    CONTEXT "High-confidence claims after seeing evidence"
    ORDER 4;
  
  -- Finally, counter-evidence
  NODE evidence WHERE relationship_type = 'contradicts'
    CONTEXT "Researchers expect to see conflicting evidence"
    ORDER 5;
END
RATIONALE "Evidence-first approach for academic rigor"
CREATED_BY "journalist_jane";
```

**Skeptic Path**:
```gql
CREATE NAVIGATION_PATH 'skeptic_path_inflation'
FOR INVESTIGATION 'uk_inflation_2023'
AUDIENCE 'SKEPTIC'
BEGIN
  -- Start with conflicts of interest
  NODE evidence ORDER BY prompt_objective DESC
    CONTEXT "Skeptics want to see bias/funding disclosed first"
    ORDER 1;
  
  -- Show counter-claims prominently
  NODE claims WHERE claim_type = 'COUNTER'
    CONTEXT "Skeptics expect to see dissenting views"
    ORDER 2;
  
  -- Then methodology scrutiny
  NODE evidence WHERE prompt_methodology < 80
    CONTEXT "Show evidence with weaker methodology for transparency"
    ORDER 3;
  
  -- Then strongest evidence
  NODE evidence WHERE prompt_overall > 90
    CONTEXT "Now show highest-quality evidence for balance"
    ORDER 4;
END
RATIONALE "Start with skepticism-relevant dimensions"
CREATED_BY "editor_bob";
```

**Affected Person Path**:
```gql
CREATE NAVIGATION_PATH 'affected_person_path_inflation'
FOR INVESTIGATION 'uk_inflation_2023'
AUDIENCE 'AFFECTED_PERSON'
BEGIN
  -- Start with personal impact
  NODE evidence WHERE evidence_type = 'personal_story'
    CONTEXT "Affected people want to see themselves reflected"
    ORDER 1;
  
  -- Then clear, simple data
  NODE evidence WHERE title LIKE '%rent%' AND prompt_transparency > 80
    CONTEXT "Rent data is directly relevant and clearly presented"
    ORDER 2;
  
  -- Then recommendations
  NODE claims WHERE claim_type = 'RECOMMENDATION'
    CONTEXT "What can I do about this?"
    ORDER 3;
END
RATIONALE "Readability and personal relevance prioritized"
CREATED_BY "journalist_jane";
```

### 4.3 Auto-Generated Paths

Lith can auto-generate paths based on heuristics:

```gql
-- Auto-generate skeptic path
GENERATE NAVIGATION_PATH 
FOR INVESTIGATION 'uk_inflation_2023'
AUDIENCE 'SKEPTIC'
STRATEGY BEGIN
  -- 1. Find lowest objective scores (potential bias)
  SELECT evidence WHERE prompt_objective < 70 LIMIT 3
  
  -- 2. Find counter-claims
  SELECT claims WHERE claim_type = 'COUNTER'
  
  -- 3. Find methodology concerns
  SELECT evidence WHERE prompt_methodology < 75 LIMIT 3
  
  -- 4. Balance with strongest evidence
  SELECT evidence WHERE prompt_overall > 90
  
  -- 5. Show consensus if exists
  SELECT claims WHERE evidence_count > 5 AND confidence_level > 0.9
END
RATIONALE "Auto-generated based on skeptic heuristics";
```

### 4.4 Path Metadata as Narrative

Paths themselves carry narrative:
```gql
INTROSPECT NAVIGATION_PATH 'researcher_path_inflation';

-- Returns:
{
  "name": "Researcher Path: UK Inflation 2023",
  "audience": "RESEARCHER",
  "created_by": "journalist_jane",
  "created_at": "2024-01-15T10:00:00Z",
  "rationale": "Evidence-first approach for academic rigor",
  "modifications": [
    { "date": "2024-01-20", "by": "editor_bob", 
      "change": "Added counter-evidence section",
      "reason": "Peer review suggested showing dissenting views earlier" }
  ],
  "usage_stats": {
    "views": 1542,
    "avg_time_spent": "8m 32s",
    "completion_rate": 0.78
  }
}
```

## 5. Journalism Workflows

### 5.1 Evidence Gathering

**Phase 1: Import from Zotero**
```gql
-- Journalist uses Zotero to manage sources
-- Lith imports with metadata mapping

INSERT INTO evidence (
  title, evidence_type, url, zotero_key,
  prompt_scores, added_by
) VALUES (
  'ONS Consumer Price Inflation, UK: 2023',
  'official_statistics',
  'https://www.ons.gov.uk/cpi/2023',
  'ZOTERO_ABC123',
  { provenance: 100, replicability: 100, objective: 95,
    methodology: 95, publication: 100, transparency: 95 },
  'reporter_alice'
)
RATIONALE "Official UK government statistics, gold standard for inflation data"
ZOTERO_TAGS ['inflation', 'UK', '2023', 'rent']
IMPORTED_AT NOW();
```

**Phase 2: Connect to Claims**
```gql
-- Reporter creates claim
INSERT INTO claims (text, claim_type, confidence_level)
VALUES (
  'Rent inflation (12%) exceeded overall inflation (8%) in 2023',
  'SUPPORTING',
  0.90
)
ADDED_BY 'reporter_alice'
RATIONALE "Synthesized from ONS CPI breakdown tables";

-- Connect evidence to claim
INSERT EDGE (claim_id, evidence_id, relationship_type, weight)
VALUES (
  'claim_rent_inflation',
  'evidence_ons_cpi_2023',
  'SUPPORTS',
  0.95
)
REASONING "ONS Table 3.2 shows rent component at 12.1%, headline CPI at 8.0%"
ADDED_BY 'reporter_alice'
VERIFIED_BY 'editor_bob';
```

### 5.2 Collaborative Editing

Multiple journalists work on same investigation:

```gql
-- Reporter Alice adds claim
INSERT INTO claims (...) ADDED_BY 'reporter_alice';

-- Editor Bob requests changes
UPDATE claims 
SET confidence_level = 0.85  -- was 0.90
WHERE id = 'claim_rent_inflation'
REASON "Reduce confidence - ONS notes preliminary data subject to revision"
EDITED_BY 'editor_bob'
EDIT_TYPE 'confidence_adjustment';

-- Reporter Alice responds
ANNOTATE claim.claim_rent_inflation
BY 'reporter_alice'
NOTE "Agreed. Final figures due March 2024, will update then.";

-- Lith journals entire conversation as narrative
```

### 5.3 Corrections and Retractions

**Scenario**: ONS revises inflation figures

```gql
-- Original claim
-- (created 2024-01-15)
claim: "Rent inflation reached 12% in 2023"
confidence: 0.90
evidence: ONS preliminary data

-- ONS releases revised figures (2024-03-01)
-- Actual: 12.7%

UPDATE claims
SET text = 'Rent inflation reached 12.7% in 2023',
    confidence_level = 0.95  -- Higher now that it's final data
WHERE id = 'claim_rent_inflation'
REASON "ONS released final 2023 figures on 2024-03-01. 
        Preliminary data (12%) underestimated actual (12.7%).
        Confidence increased as this is now final, not preliminary."
CORRECTION_TYPE 'factual_update'
DISCLOSED_AT NOW()
DISCLOSED_BY 'reporter_alice'
SOURCE_URL 'https://ons.gov.uk/final-2023-cpi';

-- Lith preserves original in journal
-- Readers see correction notice with full context
```

**Retraction** (more serious):
```gql
UPDATE claims
SET confidence_level = 0.0,
    retracted = TRUE,
    retracted_at = NOW()
WHERE id = 'claim_controversial'
REASON "Primary source retracted statement. Original interview audio 
        revealed misquote. See correction notice published 2024-02-15."
RETRACTION_TYPE 'source_error'
DISCLOSED_BY 'editor_bob'
APOLOGY "We apologize for the error and have updated our editorial 
         processes to prevent similar mistakes.";

-- Original claim remains queryable but marked retracted
-- All dependent claims are flagged for review
```

### 5.4 Fact-Checking Workflow

```gql
-- Fact-checker reviews claim
SELECT claim.text, 
       evidence.title, 
       evidence.prompt_overall,
       relationship.weight
FROM claims 
  JOIN relationships ON claims.id = relationships.from_id
  JOIN evidence ON relationships.to_id = evidence.id
WHERE claims.id = 'claim_to_check'
ORDER BY evidence.prompt_overall DESC;

-- Fact-checker adds verification note
ANNOTATE claim.claim_to_check
BY 'fact_checker_charlie'
VERIFICATION_STATUS 'verified'
NOTE "Cross-checked with 3 independent sources. ONS data confirmed.
      Academic study methodology sound (peer-reviewed, n=5000).
      Think tank report methodology less rigorous but directionally correct."
VERIFIED_AT NOW()
PROMPT_ADJUSTMENTS {
  evidence_ons_cpi: "No changes, score accurate",
  evidence_academic_study: "Increased objective score from 75→80 after bias review",
  evidence_think_tank: "No changes"
};

-- Lith journals verification as part of narrative
```

## 6. BoFIG Integration: Case Study

### 6.1 BoFIG Architecture

**BoFIG** (Binary-Origami Figuration) is an epistemic infrastructure system built on Lith.

```
┌─────────────────────────────────────────────┐
│  BoFIG Frontend (Phoenix LiveView)          │
│  - Graph visualization (D3.js)              │
│  - PROMPT scoring interface                 │
│  - Navigation path editor                   │
└────────────────┬────────────────────────────┘
                 │ GraphQL API (Absinthe)
┌────────────────▼────────────────────────────┐
│  BoFIG Business Logic (Elixir)              │
│  - Claims context                           │
│  - Evidence context                         │
│  - Relationships context                    │
│  - Navigation paths                         │
└────────────────┬────────────────────────────┘
                 │ GQL Queries
┌────────────────▼────────────────────────────┐
│  Lith (Forth/Zig/Factor)                  │
│  - Narrative-first database                 │
│  - Document + edge collections              │
│  - PROMPT scores as metadata                │
│  - Provenance tracking                      │
│  - Reversible operations                    │
└─────────────────────────────────────────────┘
```

### 6.2 Schema Mapping

**BoFIG Collections in Lith**:

```gql
-- Claims (investigative journalism claims)
CREATE COLLECTION bofig_claims (
  id UUID PRIMARY KEY,
  investigation_id VARCHAR NOT NULL,
  text TEXT NOT NULL,
  claim_type ENUM('PRIMARY', 'SUPPORTING', 'COUNTER', 'RECOMMENDATION'),
  confidence_level FLOAT CHECK (confidence_level BETWEEN 0.0 AND 1.0),
  added_by VARCHAR,
  added_at TIMESTAMP,
  last_verified TIMESTAMP,
  verified_by VARCHAR
) WITH NARRATIVE_METADATA;

-- Evidence (sources with PROMPT scores)
CREATE COLLECTION bofig_evidence (
  id UUID PRIMARY KEY,
  investigation_id VARCHAR NOT NULL,
  title VARCHAR NOT NULL,
  evidence_type ENUM('official_statistics', 'academic_study', 'think_tank', 
                     'expert_interview', 'personal_story', 'methodology'),
  url TEXT,
  zotero_key VARCHAR UNIQUE,
  prompt_scores STRUCT {
    provenance INT,
    replicability INT,
    objective INT,
    methodology INT,
    publication INT,
    transparency INT,
    overall COMPUTED AS (provenance + replicability + objective + 
                         methodology + publication + transparency) / 6.0
  },
  added_by VARCHAR,
  added_at TIMESTAMP
) WITH NARRATIVE_METADATA;

-- Relationships (claim ←→ evidence graph edges)
CREATE EDGE_COLLECTION bofig_relationships (
  from_id UUID NOT NULL,
  to_id UUID NOT NULL,
  relationship_type ENUM('SUPPORTS', 'CONTRADICTS', 'CONTEXTUALIZES'),
  weight FLOAT CHECK (weight BETWEEN 0.0 AND 1.0),
  confidence FLOAT CHECK (confidence BETWEEN 0.0 AND 1.0),
  reasoning TEXT NOT NULL,
  added_by VARCHAR,
  added_at TIMESTAMP,
  verified_by VARCHAR
) WITH NARRATIVE_METADATA;

-- Navigation Paths (boundary objects)
CREATE COLLECTION bofig_navigation_paths (
  id UUID PRIMARY KEY,
  investigation_id VARCHAR NOT NULL,
  name VARCHAR NOT NULL,
  audience_type ENUM('RESEARCHER', 'POLICYMAKER', 'SKEPTIC', 'AFFECTED_PERSON'),
  description TEXT,
  path_nodes ARRAY OF STRUCT {
    entity_id UUID,
    entity_type ENUM('CLAIM', 'EVIDENCE'),
    order INT,
    context TEXT
  },
  created_by VARCHAR,
  created_at TIMESTAMP
) WITH NARRATIVE_METADATA;
```

### 6.3 Query Examples

**GQL queries replacing AQL**:

```gql
-- Get all high-confidence claims with supporting evidence
SELECT claims.text, claims.confidence_level,
       ARRAY_AGG(evidence.title ORDER BY evidence.prompt_overall DESC) AS evidence_titles,
       AVG(evidence.prompt_overall) AS avg_evidence_quality
FROM bofig_claims AS claims
  JOIN bofig_relationships AS rel ON claims.id = rel.from_id
  JOIN bofig_evidence AS evidence ON rel.to_id = evidence.id
WHERE claims.investigation_id = 'uk_inflation_2023'
  AND claims.confidence_level >= 0.80
  AND rel.relationship_type = 'SUPPORTS'
GROUP BY claims.id
ORDER BY claims.confidence_level DESC, avg_evidence_quality DESC;

-- Get evidence chain (graph traversal)
TRAVERSE FROM claim_id 
  FOLLOW bofig_relationships OUTBOUND
  MAX_DEPTH 3
  FILTER relationship_type IN ('SUPPORTS', 'CONTEXTUALIZES')
  RETURN {
    path: path.entities,
    total_weight: SUM(path.relationships.weight),
    avg_prompt: AVG(path.entities[type='EVIDENCE'].prompt_overall)
  }
[PROVENANCE];

-- Get navigation path for skeptical audience
SELECT path.name, path.description, path.path_nodes
FROM bofig_navigation_paths AS path
WHERE path.investigation_id = 'uk_inflation_2023'
  AND path.audience_type = 'SKEPTIC'
ORDER BY path.created_at DESC
LIMIT 1;
```

### 6.4 Migration Benefits

**Before** (ArangoDB):
- ❌ No provenance tracking (who added this evidence? when? why?)
- ❌ No correction workflow (retractions require manual tracking)
- ❌ PROMPT scores are static (no history of changes)
- ❌ Relationships lack narrative (why does this edge exist?)
- ❌ No audit trail (who verified this claim?)

**After** (Lith):
- ✅ Full provenance: Every entity knows its origin
- ✅ Reversible corrections: Update with reason, preserve original
- ✅ PROMPT score evolution: Track score changes over time
- ✅ Narrative relationships: Every edge has rationale
- ✅ Complete audit trail: All operations journaled

## 7. My-Newsroom Integration

### 7.1 Multi-Agent Verification

My-Newsroom uses Dempster-Shafer belief fusion (50-100 agents) for claim verification. Lith provides the audit layer.

**Architecture**:
```
┌──────────────────────────────────────────────┐
│  My-Newsroom (Elixir/OTP Ensemble)           │
│  - 50-100 specialized agents                 │
│  - Dempster-Shafer belief fusion (Julia)     │
│  - Byzantine fault tolerance                 │
└────────────────┬─────────────────────────────┘
                 │ Audit Trail
┌────────────────▼─────────────────────────────┐
│  Lith Epistemic Ledger                     │
│  - Every belief fusion recorded              │
│  - Agent reasoning preserved                 │
│  - Conflicts/resolutions journaled           │
└──────────────────────────────────────────────┘
```

### 7.2 Belief Fusion Audit Trail

```gql
CREATE COLLECTION newsroom_belief_fusions (
  fusion_id UUID PRIMARY KEY,
  claim_text TEXT NOT NULL,
  agent_pool ARRAY OF VARCHAR,  -- ["agent_reporter_politics", "agent_fact_checker", ...]
  individual_beliefs ARRAY OF STRUCT {
    agent_id VARCHAR,
    belief FLOAT,  -- 0.0-1.0
    mass_function JSONB,  -- Dempster-Shafer mass function
    rationale TEXT,
    sources_cited ARRAY OF VARCHAR
  },
  fusion_method ENUM('Dempster', 'Yager', 'DuboisPrade', 'Average'),
  fusion_result STRUCT {
    fused_belief FLOAT,
    fused_mass JSONB,
    conflict_measure FLOAT,
    confidence_interval STRUCT {lower FLOAT, upper FLOAT}
  },
  consensus_reached BOOLEAN,
  consensus_threshold FLOAT,
  fused_by VARCHAR,  -- Orchestrator agent
  fused_at TIMESTAMP
) WITH NARRATIVE_METADATA;

-- Example: Claim verification
INSERT INTO newsroom_belief_fusions (
  claim_text, agent_pool, individual_beliefs,
  fusion_method, fusion_result, consensus_reached
) VALUES (
  'UK rent inflation exceeded 12% in 2023',
  ['agent_reporter_economics', 'agent_fact_checker_primary', 'agent_editor_senior'],
  [
    { agent_id: 'agent_reporter_economics',
      belief: 0.90,
      mass_function: '{"{{true}}": 0.90, "Θ": 0.10}',
      rationale: 'ONS data Table 3.2 shows 12.1% rent component',
      sources_cited: ['evidence_ons_cpi_2023'] },
    { agent_id: 'agent_fact_checker_primary',
      belief: 0.85,
      mass_function: '{"{{true}}": 0.85, "Θ": 0.15}',
      rationale: 'Cross-checked with 3 sources, slight variations (11.8-12.3%)',
      sources_cited: ['evidence_ons_cpi_2023', 'evidence_academic_study', 'evidence_think_tank'] },
    { agent_id: 'agent_editor_senior',
      belief: 0.95,
      mass_function: '{"{{true}}": 0.95, "Θ": 0.05}',
      rationale: 'Final ONS figures released, no longer preliminary',
      sources_cited: ['evidence_ons_final_2023'] }
  ],
  'Dempster',
  {
    fused_belief: 0.92,
    fused_mass: '{"{{true}}": 0.92, "Θ": 0.08}',
    conflict_measure: 0.03,
    confidence_interval: {lower: 0.88, upper: 0.96}
  },
  TRUE  -- Consensus reached
)
FUSED_BY 'orchestrator_agent_main'
RATIONALE "Three agents agree with high confidence. Low conflict (0.03).
           Consensus threshold (0.85) exceeded. Claim verified."
[PROVENANCE];
```

### 7.3 Agent Introspection

Agents query their own reasoning history:

```gql
-- Agent asks: "What claims have I verified about inflation?"
SELECT fusion.claim_text, 
       belief.belief,
       belief.rationale,
       fusion.fusion_result.fused_belief,
       fusion.consensus_reached
FROM newsroom_belief_fusions AS fusion,
     UNNEST(fusion.individual_beliefs) AS belief
WHERE belief.agent_id = 'agent_reporter_economics'
  AND fusion.claim_text LIKE '%inflation%'
ORDER BY fusion.fused_at DESC
[PROVENANCE];

-- Returns:
-- [
--   { claim: "UK rent inflation exceeded 12% in 2023",
--     my_belief: 0.90,
--     my_rationale: "ONS data Table 3.2 shows 12.1% rent component",
--     consensus: 0.92,
--     consensus_reached: true,
--     timestamp: "2024-01-15T14:30:00Z" },
--   ...
-- ]
```

### 7.4 Conflict Resolution Narrative

When agents disagree:

```gql
-- Agents disagree on controversial claim
INSERT INTO newsroom_belief_fusions (
  claim_text, individual_beliefs, fusion_method, fusion_result, consensus_reached
) VALUES (
  'Government inflation target was achievable in 2023',
  [
    { agent: 'agent_economist_keynesian', belief: 0.30, 
      rationale: 'Structural factors made 2% target unrealistic' },
    { agent: 'agent_economist_monetarist', belief: 0.75,
      rationale: 'BoE had tools but lacked political will' },
    { agent: 'agent_policy_analyst', belief: 0.50,
      rationale: 'Uncertain - depends on counterfactuals' }
  ],
  'DuboisPrade',  -- Use DuboisPrade for high-conflict scenarios
  {
    fused_belief: 0.52,
    conflict_measure: 0.45,  -- HIGH CONFLICT
    confidence_interval: {lower: 0.30, upper: 0.75}
  },
  FALSE  -- No consensus
)
RATIONALE "High conflict (0.45) due to ideological differences.
           DuboisPrade fusion used (handles conflict better than Dempster).
           No consensus reached - mark claim as CONTESTED.
           Editor review required."
REQUIRES_HUMAN_REVIEW TRUE
[PROVENANCE];

-- Lith journals this as a contested claim
-- Readers see: "This claim is disputed among experts (consensus: 52%, conflict: high)"
```

## 8. Implementation Roadmap

### Phase 1: Lith Core for BoFIG (Month 1-3)

- [ ] Migrate BoFIG from ArangoDB to Lith
- [ ] Implement PROMPT score schema
- [ ] Build navigation path collections
- [ ] Create GQL equivalents for all current AQL queries
- [ ] Migrate UK Inflation 2023 test dataset
- [ ] Test with NUJ journalists (25 users)

### Phase 2: Zotero Integration (Month 4-6)

- [ ] Formalize Zotero metadata → Lith mapping
- [ ] Build browser extension (import from Zotero to Lith)
- [ ] Implement two-way sync (changes in Lith → Zotero)
- [ ] PROMPT score estimation from Zotero tags
- [ ] Citation graph import (related works)

### Phase 3: My-Newsroom Integration (Month 7-12)

- [ ] Define belief fusion audit schema
- [ ] Build Elixir adapter (My-Newsroom → Lith)
- [ ] Implement agent introspection queries
- [ ] Build conflict resolution workflow
- [ ] Test with 10-agent newsroom (proof-of-concept)

### Phase 4: i-doc Platform (Month 13-18)

- [ ] D3.js visualization (evidence graphs)
- [ ] LiveView UI (interactive navigation)
- [ ] Auto-generate navigation paths
- [ ] Embed PROMPT scoring interface
- [ ] Public-facing i-doc viewer

### Phase 5: Scale to Reuters-level Newsroom (Month 19-24)

- [ ] 50-100 agent deployment (My-Newsroom full scale)
- [ ] Byzantine fault tolerance testing
- [ ] Distributed Lith (Raft consensus, sharding)
- [ ] Real-time collaboration (Phoenix Channels)
- [ ] IPFS provenance integration

## 9. Evaluation Metrics

### 9.1 Journalism Quality

- **Correction Rate**: % of claims corrected within 30 days
  - **Target**: <5% (high initial accuracy)
  - **Metric**: `SELECT COUNT(*) FROM claims WHERE corrected = TRUE / COUNT(*)`

- **Retraction Rate**: % of claims fully retracted
  - **Target**: <1% (rare, serious errors)
  - **Metric**: `SELECT COUNT(*) FROM claims WHERE retracted = TRUE / COUNT(*)`

- **Average PROMPT Score**: Quality of evidence base
  - **Target**: >75 (acceptable quality)
  - **Metric**: `SELECT AVG(prompt_overall) FROM evidence`

- **Verification Latency**: Time from claim to verification
  - **Target**: <48 hours
  - **Metric**: `SELECT AVG(verified_at - added_at) FROM claims WHERE verified_by IS NOT NULL`

### 9.2 Reader Engagement

- **Navigation Path Completion**: % of readers who complete path
  - **Target**: >60%
  - **Tracked via**: Frontend analytics + Lith queries

- **Average Time on Evidence**: Reader engagement depth
  - **Target**: >3 minutes per evidence item
  - **Tracked via**: Frontend analytics

- **Perspective Diversity**: % readers exploring multiple paths
  - **Target**: >30% try 2+ audience paths
  - **Tracked via**: Session tracking

### 9.3 Agent Performance

- **Consensus Rate**: % of claims reaching agent consensus
  - **Target**: >80% (most claims should converge)
  - **Metric**: `SELECT COUNT(*) WHERE consensus_reached = TRUE / COUNT(*)`

- **Conflict Detection**: % of genuine conflicts identified
  - **Target**: >90% (high sensitivity)
  - **Metric**: Manual review of high-conflict fusions

- **Byzantine Resilience**: % of attacks detected/prevented
  - **Target**: 100% up to 33% malicious agents
  - **Tested via**: Adversarial agent injection

## 10. Related Work

### 10.1 i-doc Platforms

- **Korsakow** (Florian Thalhofer): Interactive documentary authoring
  - **Gap**: No provenance tracking, no PROMPT scores
- **Zeega** (Zeega Project): Multi-layered storytelling
  - **Gap**: No epistemological metadata
- **Eko** (Formerly Interlude): Interactive video platform
  - **Gap**: Entertainment-focused, not journalism

**Lith Advantage**: Purpose-built for journalism epistemology.

### 10.2 Fact-Checking Systems

- **ClaimBuster** (UTA): Automated claim detection
  - **Gap**: No narrative database, no evidence tracking
- **Full Fact** (UK): Manual fact-checking
  - **Gap**: Uses traditional databases, no provenance
- **PolitiFact** (Poynter): Truth-O-Meter ratings
  - **Gap**: Ratings are final, no correction workflow

**Lith Advantage**: Treats corrections as first-class operations.

### 10.3 Evidence Management

- **Zotero**: Reference management
  - **Integration**: Lith imports from Zotero
- **ResearchRabbit**: Citation graph visualization
  - **Gap**: No epistemological scoring
- **Scite**: Citation context (supporting/contrasting)
  - **Inspiration**: Similar to Lith's relationship types

**Lith Advantage**: Combines evidence management + epistemology + narrative.

## 11. Open Questions

See `lith.scm` Q-IDOC-* questions:

1. **Q-IDOC-PROMPT-001**: Should PROMPT scores be normalized across investigations?
   - **Issue**: Different domains have different score distributions
   - **Proposal**: Domain-specific normalization curves

2. **Q-IDOC-PATH-001**: How to measure navigation path effectiveness?
   - **Metrics**: Completion rate, time spent, user satisfaction
   - **Proposal**: A/B testing of auto-generated vs. manual paths

3. **Q-IDOC-CORRECTION-001**: When should corrections trigger re-verification?
   - **Threshold**: Major corrections (>10% confidence change)?
   - **Proposal**: Cascading re-verification for dependent claims

4. **Q-IDOC-AGENT-001**: How many agents needed for reliable consensus?
   - **Minimum**: 3 (for voting)
   - **Optimal**: 7-15 (diminishing returns beyond this)
   - **Research needed**: Empirical studies

## 12. Conclusion

Lith is not just a database for journalism—it is **infrastructure for epistemology in the post-truth era**. By making provenance, corrections, and multi-perspective navigation first-class database semantics, Lith enables:

1. **i-docs at scale**: Navigation over narration, reader agency
2. **Transparent epistemology**: PROMPT scores, evidence chains
3. **Correction workflows**: Retractions with full context
4. **Multi-agent verification**: Dempster-Shafer fusion audit trails
5. **Boundary objects**: Same evidence, multiple audience perspectives

BoFIG demonstrates Lith's practical application in investigative journalism. My-Newsroom extends this to multi-agent verification. Together, they form a complete epistemic infrastructure stack for journalism in the 21st century.

**Next Steps**:
1. Migrate BoFIG from ArangoDB to Lith (Month 1-3)
2. User testing with NUJ journalists (Month 3, 6, 12)
3. My-Newsroom integration (Month 7-12)
4. Full-scale Reuters-level newsroom (Month 19-24)

**Impact**: Lith + BoFIG + My-Newsroom could become the **de facto standard** for i-doc journalism, much as Zotero became the standard for academic reference management.

---

**Document Status**: Living document. Updates tracked in `spec/WP05_CHANGELOG.md`.

**See Also**:
- [BoFIG Repository](https://github.com/Hyperpolymath/bofig)
- [My-Newsroom Repository](https://github.com/hyperpolymath/my-newsroom)
- [MIT Open Doc Lab](https://opendoclab.mit.edu/)
- [PROMPT Framework](https://example.com/prompt-framework)
