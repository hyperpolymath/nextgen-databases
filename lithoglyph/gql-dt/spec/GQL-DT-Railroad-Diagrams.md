# GQL-DT Railroad Diagrams

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

**Version:** 1.0.0
**Date:** 2026-02-01

This document provides railroad diagram specifications for GQL-DT syntax. These can be used with:
- **Online:** https://www.bottlecaps.de/rr/ui
- **CLI:** `rr` (Railroad Diagram Generator)
- **Graphviz:** Convert to DOT format

## Table of Contents

1. [CREATE COLLECTION](#create-collection)
2. [INSERT Statement](#insert-statement)
3. [SELECT Statement](#select-statement)
4. [Type Expressions](#type-expressions)
5. [Proof Clauses](#proof-clauses)
6. [UPDATE Statement](#update-statement)
7. [Normalization Commands](#normalization-commands)

---

## 1. CREATE COLLECTION

### Railroad Diagram Source (EBNF)

```ebnf
CreateCollection ::= 'CREATE' 'COLLECTION' ('IF' 'NOT' 'EXISTS')?
                     Identifier
                     '(' ColumnList ')'
                     CollectionOptions?

ColumnList ::= ColumnDef (',' ColumnDef)*

ColumnDef ::= Identifier ':' TypeExpr

CollectionOptions ::= 'WITH' OptionList

OptionList ::= Option (',' Option)*

Option ::= 'DEPENDENT_TYPES'
         | 'PROVENANCE_TRACKING'
         | 'TARGET_NORMAL_FORM' NormalForm
         | 'FUNCTIONAL_DEPENDENCIES' '(' FDList ')'
```

### ASCII Railroad Diagram

```
CREATE COLLECTION ─┬─────────────────────┬─ Identifier ─┬─ ( ─ ColumnList ─ ) ─┬────────────────────────┬──
                   └─ IF NOT EXISTS ─────┘              └─────────────────────────┘                        └──┘
                                                                                  └─ WITH ─ OptionList ─┘

ColumnDef:
Identifier ─ : ─ TypeExpr ──

Option:
┌─ DEPENDENT_TYPES ───────────────────────────────┐
├─ PROVENANCE_TRACKING ───────────────────────────┤
├─ TARGET_NORMAL_FORM ─ NormalForm ───────────────┤
└─ FUNCTIONAL_DEPENDENCIES ─ ( ─ FDList ─ ) ─────┘
```

---

## 2. INSERT Statement

### Railroad Diagram Source (EBNF)

```ebnf
InsertStatement ::= 'INSERT' 'INTO' Identifier
                    ('(' ColumnNames ')')?
                    'VALUES' '(' ValueList ')'
                    RationaleClause
                    ('ADDED_BY' StringLiteral)?
                    ('WITH_PROOF' ProofBlock)?
                    InverseClause?

RationaleClause ::= 'RATIONALE' StringLiteral
                  | 'REASON' StringLiteral

ProofBlock ::= '{' ProofList '}'

ProofList ::= ProofObligation (',' ProofObligation)*

ProofObligation ::= Identifier ':' ProofTerm

ProofTerm ::= 'by' TacticExpr
            | LeanProof

InverseClause ::= 'WITH_INVERSE' '(' Statement ')'
                | 'IRREVERSIBLE' 'BECAUSE' StringLiteral
                  ('WITH_JUSTIFICATION' Justification)?
```

### ASCII Railroad Diagram

```
INSERT INTO ─ Identifier ─┬──────────────────────────────┬─ VALUES ─ ( ─ ValueList ─ ) ─ RationaleClause ─┬────────────────────────────┬─┬─────────────────────┬─┬──────────────────┬──
                          └─ ( ─ ColumnNames ─ ) ───────┘                                                  └─ ADDED_BY ─ String ───────┘ └─ WITH_PROOF ─ {...}─┘ └─ InverseClause ─┘

RationaleClause:
┌─ RATIONALE ─ StringLiteral ─┐
└─ REASON ─ StringLiteral ─────┘

InverseClause:
┌─ WITH_INVERSE ─ ( ─ Statement ─ ) ───────────────────────────────┐
└─ IRREVERSIBLE ─ BECAUSE ─ String ─┬──────────────────────────────┤
                                    └─ WITH_JUSTIFICATION ─ {...} ─┘
```

---

## 3. SELECT Statement

### Railroad Diagram Source (EBNF)

```ebnf
SelectStatement ::= 'SELECT' SelectList
                    'FROM' FromClause
                    JoinClause?
                    ('WHERE' Condition)?
                    ('GROUP' 'BY' ExprList)?
                    ('ORDER' 'BY' OrderList)?
                    ('LIMIT' NatLiteral)?
                    ('RETURNING' TypeRefinement)?
                    ('[' 'VERIFY_PROOFS' ']')?

SelectList ::= '*'
             | SelectExpr (',' SelectExpr)*
             | TypeRefinement

FromClause ::= TableRef (',' TableRef)*

JoinClause ::= Join+

Join ::= ('INNER' | 'LEFT' | 'RIGHT' | 'FULL')?
         'JOIN' TableRef 'ON' Condition

TypeRefinement ::= '(' Identifier ':' TypeExpr ('|' Condition)? ')'
```

### ASCII Railroad Diagram

```
SELECT ─┬─ * ─────────────┬─ FROM ─ FromClause ─┬──────────────┬─┬──────────────────┬─┬─────────────────────┬─┬────────────────────┬─┬────────────────┬─┬────────────────────────┬─┬───────────────────┬──
        ├─ SelectExpr ... ─┤                     └─ JoinClause ─┘ └─ WHERE ─ Cond ──┘ └─ GROUP BY ─ Expr ──┘ └─ ORDER BY ─ Order ─┘ └─ LIMIT ─ Nat ─┘ └─ RETURNING ─ TypeRef ─┘ └─ [VERIFY_PROOFS] ─┘
        └─ TypeRefinement ─┘

Join:
┬────────┬─ JOIN ─ TableRef ─ ON ─ Condition ──
└─ INNER ┤
  LEFT   │
  RIGHT  │
  FULL  ─┘

TypeRefinement:
( ─ Identifier ─ : ─ TypeExpr ─┬──────────────┬─ ) ──
                                └─ | ─ Cond ──┘
```

---

## 4. Type Expressions

### Railroad Diagram Source (EBNF)

```ebnf
TypeExpr ::= PrimitiveType
           | RefinedType
           | DependentType
           | FunctionType
           | ProductType
           | QuantifiedType

PrimitiveType ::= 'Nat' | 'Int' | 'String' | 'Bool' | 'Float' |
                  'Char' | 'Unit' | 'UUID' | 'Timestamp'

RefinedType ::= 'BoundedNat' NatLiteral NatLiteral
              | 'BoundedFloat' FloatLiteral FloatLiteral
              | 'NonEmptyString'
              | 'Email'
              | 'Confidence'
              | 'PromptDimension'

DependentType ::= 'Vector' TypeExpr NatLiteral
                | 'Tracked' TypeExpr
                | 'PromptScores'
                | 'NavigationPath' LambdaExpr
                | 'Claim' ConfidenceExpr

FunctionType ::= TypeExpr '->' TypeExpr
               | '(' ParamList ')' '->' TypeExpr

ProductType ::= TypeExpr '×' TypeExpr
              | '(' TypeExpr (',' TypeExpr)+ ')'

QuantifiedType ::= '∀' '(' ParamDef ')' ',' TypeExpr
                 | '∃' '(' ParamDef ')' ',' TypeExpr
```

### ASCII Railroad Diagram

```
TypeExpr:
┌─ PrimitiveType ─────────────────┐
├─ RefinedType ───────────────────┤
├─ DependentType ─────────────────┤
├─ FunctionType ──────────────────┤
├─ ProductType ───────────────────┤
└─ QuantifiedType ────────────────┘

RefinedType:
┌─ BoundedNat ─ Nat ─ Nat ────────┐
├─ BoundedFloat ─ Float ─ Float ──┤
├─ NonEmptyString ────────────────┤
├─ Email ─────────────────────────┤
├─ Confidence ────────────────────┤
└─ PromptDimension ───────────────┘

DependentType:
┌─ Vector ─ TypeExpr ─ Nat ──────────┐
├─ Tracked ─ TypeExpr ───────────────┤
├─ PromptScores ─────────────────────┤
├─ NavigationPath ─ LambdaExpr ──────┤
└─ Claim ─ ConfidenceExpr ───────────┘

FunctionType:
┌─ TypeExpr ─ -> ─ TypeExpr ────────────────┐
└─ ( ─ ParamList ─ ) ─ -> ─ TypeExpr ───────┘
```

---

## 5. Proof Clauses

### Railroad Diagram Source (EBNF)

```ebnf
ProofClause ::= 'WITH_PROOF' ProofBlock

ProofBlock ::= '{' ProofList '}'

ProofList ::= ProofObligation (',' ProofObligation)*

ProofObligation ::= Identifier ':' ProofTerm

ProofTerm ::= 'by' TacticExpr
            | LeanProof

TacticExpr ::= Identifier TacticArgs?
             | TacticExpr ';' TacticExpr
             | TacticExpr '<|>' TacticExpr
             | 'first' '|' TacticExpr ('|' TacticExpr)*
```

### ASCII Railroad Diagram

```
WITH_PROOF ─ { ─ ProofList ─ } ──

ProofList:
ProofObligation ─┬────────────────────────────┬──
                 └─ , ─ ProofObligation ──────┘ (loop)

ProofObligation:
Identifier ─ : ─ ProofTerm ──

ProofTerm:
┌─ by ─ TacticExpr ─┐
└─ LeanProof ────────┘

TacticExpr:
┌─ Identifier ─┬───────────────┬────────────────────────────────────────┐
│              └─ TacticArgs ──┘                                        │
├─ TacticExpr ─ ; ─ TacticExpr ─────────────────────────────────────────┤
├─ TacticExpr ─ <|> ─ TacticExpr ───────────────────────────────────────┤
└─ first ─ | ─ TacticExpr ─┬───────────────────────┬─────────────────────┘
                           └─ | ─ TacticExpr ──────┘ (loop)
```

---

## 6. UPDATE Statement

### Railroad Diagram Source (EBNF)

```ebnf
UpdateStatement ::= 'UPDATE' Identifier
                    'SET' AssignmentList
                    'WHERE' Condition
                    RationaleClause
                    ('CORRECTION_TYPE' StringLiteral)?
                    ('DISCLOSED_AT' (TimestampLiteral | 'NOW' '(' ')'))?
                    ('DISCLOSED_BY' StringLiteral)?
                    ('WITH_PROOF' ProofBlock)?
                    InverseClause?

AssignmentList ::= Assignment (',' Assignment)*

Assignment ::= Identifier '=' Value
```

### ASCII Railroad Diagram

```
UPDATE ─ Identifier ─ SET ─ AssignmentList ─ WHERE ─ Condition ─ RationaleClause ─┬────────────────────────────┬─┬──────────────────────┬─┬───────────────────────┬─┬─────────────────────┬─┬──────────────────┬──
                                                                                   └─ CORRECTION_TYPE ─ String ─┘ └─ DISCLOSED_AT ─ ... ─┘ └─ DISCLOSED_BY ─ String ─┘ └─ WITH_PROOF ─ {...}─┘ └─ InverseClause ─┘

AssignmentList:
Assignment ─┬───────────────────┬──
            └─ , ─ Assignment ──┘ (loop)

Assignment:
Identifier ─ = ─ Value ──
```

---

## 7. Normalization Commands

### Railroad Diagram Source (EBNF)

```ebnf
DiscoverDependencies ::= 'DISCOVER' 'DEPENDENCIES'
                         'FROM' Identifier
                         ('SAMPLE' NatLiteral)?
                         ('CONFIDENCE' FloatLiteral)?
                         ('RETURNING' TypeRefinement)?

CheckNormalForm ::= 'CHECK' 'NORMAL_FORM' Identifier
                    'AGAINST' NormalForm
                    ('RETURNING' TypeRefinement)?

ProposeNormalization ::= 'PROPOSE' 'NORMALIZATION' Identifier
                         'TO' NormalForm
                         ('STRATEGY' Strategy)?
                         ('RETURNING' TypeRefinement)?

ApplyNormalization ::= 'APPLY' 'NORMALIZATION' Identifier
                       ProofClause
                       RationaleClause
```

### ASCII Railroad Diagram

```
DISCOVER DEPENDENCIES ─ FROM ─ Identifier ─┬────────────────┬─┬──────────────────────┬─┬────────────────────────┬──
                                           └─ SAMPLE ─ Nat ─┘ └─ CONFIDENCE ─ Float ─┘ └─ RETURNING ─ TypeRef ─┘

CHECK NORMAL_FORM ─ Identifier ─ AGAINST ─ NormalForm ─┬────────────────────────┬──
                                                        └─ RETURNING ─ TypeRef ─┘

PROPOSE NORMALIZATION ─ Identifier ─ TO ─ NormalForm ─┬─────────────────────┬─┬────────────────────────┬──
                                                       └─ STRATEGY ─ Strat ──┘ └─ RETURNING ─ TypeRef ─┘

APPLY NORMALIZATION ─ Identifier ─ ProofClause ─ RationaleClause ──
```

---

## 8. Lambda Expressions

### Railroad Diagram Source (EBNF)

```ebnf
LambdaExpr ::= ('λ' | '\') ParamList '.' Expr

ParamList ::= Identifier (',' Identifier)*

Expr ::= Literal
       | Identifier
       | LambdaExpr
       | ApplicationExpr
       | InfixExpr
       | '(' Expr ')'

ApplicationExpr ::= Expr Expr

InfixExpr ::= Expr InfixOp Expr
```

### ASCII Railroad Diagram

```
┌─ λ ─┬─ ParamList ─ . ─ Expr ──
└─ \ ─┘

ParamList:
Identifier ─┬────────────────────┬──
            └─ , ─ Identifier ───┘ (loop)

Expr:
┌─ Literal ────────────┐
├─ Identifier ─────────┤
├─ LambdaExpr ─────────┤
├─ ApplicationExpr ────┤
├─ InfixExpr ──────────┤
└─ ( ─ Expr ─ ) ───────┘

InfixExpr:
Expr ─ InfixOp ─ Expr ──
```

---

## 9. Struct and Array Literals

### Railroad Diagram Source (EBNF)

```ebnf
StructLiteral ::= '{' FieldList '}'

FieldList ::= FieldAssignment (',' FieldAssignment)*

FieldAssignment ::= Identifier ':' Value

ArrayLiteral ::= '[' ValueList ']'

ValueList ::= Value (',' Value)*
```

### ASCII Railroad Diagram

```
StructLiteral:
{ ─ FieldList ─ } ──

FieldList:
FieldAssignment ─┬─────────────────────────┬──
                 └─ , ─ FieldAssignment ───┘ (loop)

FieldAssignment:
Identifier ─ : ─ Value ──

ArrayLiteral:
[ ─ ValueList ─ ] ──

ValueList:
Value ─┬──────────────┬──
       └─ , ─ Value ──┘ (loop)
```

---

## 10. Complete Example Diagrams

### Example: INSERT with All Optional Clauses

```
INSERT INTO evidence ─ ( ─ title, prompt_scores ─ ) ─
VALUES ─ ( ─ 'ONS Data', {...} ─ ) ─
RATIONALE ─ "Official statistics" ─
ADDED_BY ─ "alice" ─
WITH_PROOF ─ {
  scores_in_bounds: by lithoglyph_prompt,
  overall_correct: by lithoglyph_prompt
} ─
WITH_INVERSE ─ ( ─ DELETE FROM evidence WHERE id = $GENERATED_ID ─ ) ──
```

### Example: SELECT with Type Refinement

```
SELECT ─ ( ─ e : Evidence | e.prompt_overall > 90 ─ ) ─
FROM ─ evidence e ─
WHERE ─ investigation_id = 'uk_inflation_2023' ─
RETURNING ─ ( ─ List ─ ( ─ Evidence | prompt_overall > 90 ─ ) ─ ) ──
```

---

## 11. Usage Instructions

### Online Railroad Diagram Generator

1. Visit https://www.bottlecaps.de/rr/ui
2. Paste EBNF from sections above
3. Click "View Diagram"
4. Export as SVG or PNG

### CLI Tool

```bash
# Install rr (Railroad Diagram Generator)
npm install -g railroad-diagrams

# Generate diagrams
rr < GQL-DT-Grammar.ebnf > diagrams.html
```

### Integration with Spec

Generated SVG files should be placed in:
```
spec/diagrams/
├── create-collection.svg
├── insert-statement.svg
├── select-statement.svg
├── type-expressions.svg
├── proof-clauses.svg
├── update-statement.svg
└── normalization-commands.svg
```

---

## 12. Diagram Conventions

### Notation

- **Railroad tracks** - Syntax flow
- **Boxes** - Terminals (keywords, operators)
- **Rounded boxes** - Non-terminals (rules)
- **Arrows** - Sequence direction
- **Splits** - Alternatives (OR)
- **Loops** - Repetition (zero or more, one or more)

### Reading Direction

- **Left to right** - Primary flow
- **Top to bottom** - Alternatives

### Colors (if generating colored diagrams)

- **Blue boxes** - Keywords
- **Green boxes** - Terminals (literals, operators)
- **Orange boxes** - Non-terminals (references to other rules)
- **Gray tracks** - Optional paths

---

## References

1. **Railroad Diagram Generator:** https://www.bottlecaps.de/rr/ui
2. **EBNF Standard:** ISO/IEC 14977
3. **GQL-DT Grammar:** `GQL-DT-Grammar.ebnf`
4. **W3C EBNF Notation:** https://www.w3.org/TR/REC-xml/#sec-notation

---

**Document Status:** Complete railroad diagram specifications for GQL-DT v1.0

**Next Steps:**
1. Generate SVG diagrams using online tool
2. Place in `spec/diagrams/` directory
3. Reference from main specification document
4. Update as grammar evolves

**See Also:**
- `GQL-DT-Grammar.ebnf` - Formal EBNF grammar source
- `GQL-DT-Lexical.md` - Lexical specification
- `GQL_Dependent_Types_Complete_Specification.md` - Type system spec
