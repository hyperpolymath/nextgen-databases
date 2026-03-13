<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith\Query;

use Lith\Types\Provenance;

/**
 * Comparison operators
 */
enum CompareOp: string
{
    case EQ = '=';
    case NE = '!=';
    case LT = '<';
    case LE = '<=';
    case GT = '>';
    case GE = '>=';
    case LIKE = 'LIKE';
    case IN = 'IN';
}

/**
 * Filter expression interface
 */
interface FilterExpr
{
    public function toFdql(): string;
}

/**
 * Field comparison filter
 */
final class FieldFilter implements FilterExpr
{
    public function __construct(
        public readonly string $field,
        public readonly CompareOp $op,
        public readonly mixed $value,
    ) {}

    public function toFdql(): string
    {
        $valueStr = match (true) {
            is_string($this->value) => '"' . addslashes($this->value) . '"',
            is_bool($this->value) => $this->value ? 'true' : 'false',
            is_null($this->value) => 'null',
            is_array($this->value) => '(' . implode(', ', array_map(
                fn($v) => is_string($v) ? '"' . addslashes($v) . '"' : (string) $v,
                $this->value
            )) . ')',
            default => (string) $this->value,
        };

        return "{$this->field} {$this->op->value} {$valueStr}";
    }
}

/**
 * AND filter
 */
final class AndFilter implements FilterExpr
{
    public function __construct(
        public readonly FilterExpr $left,
        public readonly FilterExpr $right,
    ) {}

    public function toFdql(): string
    {
        return '(' . $this->left->toFdql() . ' AND ' . $this->right->toFdql() . ')';
    }
}

/**
 * OR filter
 */
final class OrFilter implements FilterExpr
{
    public function __construct(
        public readonly FilterExpr $left,
        public readonly FilterExpr $right,
    ) {}

    public function toFdql(): string
    {
        return '(' . $this->left->toFdql() . ' OR ' . $this->right->toFdql() . ')';
    }
}

/**
 * NOT filter
 */
final class NotFilter implements FilterExpr
{
    public function __construct(
        public readonly FilterExpr $filter,
    ) {}

    public function toFdql(): string
    {
        return 'NOT (' . $this->filter->toFdql() . ')';
    }
}

/**
 * Fluent query builder for SELECT queries
 */
final class QueryBuilder
{
    private ?string $collection = null;
    /** @var string[]|null */
    private ?array $fields = null;
    private ?FilterExpr $filter = null;
    private ?int $limit = null;
    private ?int $offset = null;
    private ?string $orderByField = null;
    private bool $orderAscending = true;
    private ?Provenance $provenance = null;

    /**
     * Set the collection to query
     */
    public function from(string $collection): self
    {
        $this->collection = $collection;
        return $this;
    }

    /**
     * Alias for from()
     */
    public function collection(string $collection): self
    {
        return $this->from($collection);
    }

    /**
     * Set fields to select
     * @param string[] $fields
     */
    public function select(array $fields): self
    {
        $this->fields = $fields;
        return $this;
    }

    /**
     * Add a WHERE filter expression
     */
    public function where(FilterExpr $filter): self
    {
        if ($this->filter === null) {
            $this->filter = $filter;
        } else {
            $this->filter = new AndFilter($this->filter, $filter);
        }
        return $this;
    }

    /**
     * Add a field comparison filter (convenience method)
     */
    public function whereField(string $field, CompareOp|string $op, mixed $value): self
    {
        $op = is_string($op) ? CompareOp::from($op) : $op;
        return $this->where(new FieldFilter($field, $op, $value));
    }

    /**
     * Set limit
     */
    public function limit(int $limit): self
    {
        $this->limit = $limit;
        return $this;
    }

    /**
     * Set offset
     */
    public function offset(int $offset): self
    {
        $this->offset = $offset;
        return $this;
    }

    /**
     * Set order by
     */
    public function orderBy(string $field, bool $ascending = true): self
    {
        $this->orderByField = $field;
        $this->orderAscending = $ascending;
        return $this;
    }

    /**
     * Add provenance metadata
     */
    public function withProvenance(string|Provenance $actorOrProvenance, ?string $rationale = null): self
    {
        if ($actorOrProvenance instanceof Provenance) {
            $this->provenance = $actorOrProvenance;
        } else {
            $this->provenance = new Provenance($actorOrProvenance, $rationale ?? '');
        }
        return $this;
    }

    /**
     * Build the FDQL query string
     */
    public function toFdql(): string
    {
        if ($this->collection === null) {
            throw new \RuntimeException('Collection is required');
        }

        $fieldsStr = $this->fields !== null ? implode(', ', $this->fields) : '*';
        $query = "SELECT {$fieldsStr} FROM {$this->collection}";

        if ($this->filter !== null) {
            $query .= ' WHERE ' . $this->filter->toFdql();
        }

        if ($this->orderByField !== null) {
            $dir = $this->orderAscending ? 'ASC' : 'DESC';
            $query .= " ORDER BY {$this->orderByField} {$dir}";
        }

        if ($this->limit !== null) {
            $query .= " LIMIT {$this->limit}";
        }

        if ($this->offset !== null) {
            $query .= " OFFSET {$this->offset}";
        }

        if ($this->provenance !== null) {
            $query .= ' WITH PROVENANCE { actor: "' . addslashes($this->provenance->actor) . '", rationale: "' . addslashes($this->provenance->rationale) . '" }';
        }

        return $query;
    }

    /**
     * Get the provenance (for client to use)
     */
    public function getProvenance(): ?Provenance
    {
        return $this->provenance;
    }
}

/**
 * Fluent builder for INSERT statements
 */
final class InsertBuilder
{
    private ?string $collection = null;
    /** @var array<string, mixed>|null */
    private ?array $document = null;
    private ?Provenance $provenance = null;

    /**
     * Set the collection to insert into
     */
    public function into(string $collection): self
    {
        $this->collection = $collection;
        return $this;
    }

    /**
     * Set the document to insert
     * @param array<string, mixed> $document
     */
    public function values(array $document): self
    {
        $this->document = $document;
        return $this;
    }

    /**
     * Add provenance metadata
     */
    public function withProvenance(string|Provenance $actorOrProvenance, ?string $rationale = null): self
    {
        if ($actorOrProvenance instanceof Provenance) {
            $this->provenance = $actorOrProvenance;
        } else {
            $this->provenance = new Provenance($actorOrProvenance, $rationale ?? '');
        }
        return $this;
    }

    /**
     * Build the FDQL insert string
     */
    public function toFdql(): string
    {
        if ($this->collection === null) {
            throw new \RuntimeException('Collection is required');
        }
        if ($this->document === null) {
            throw new \RuntimeException('Document is required');
        }

        $docJson = json_encode($this->document, JSON_THROW_ON_ERROR);
        $query = "INSERT INTO {$this->collection} {$docJson}";

        if ($this->provenance !== null) {
            $query .= ' WITH PROVENANCE { actor: "' . addslashes($this->provenance->actor) . '", rationale: "' . addslashes($this->provenance->rationale) . '" }';
        }

        return $query;
    }

    public function getProvenance(): ?Provenance
    {
        return $this->provenance;
    }
}

/**
 * Fluent builder for UPDATE statements
 */
final class UpdateBuilder
{
    private ?string $collection = null;
    /** @var array<string, mixed> */
    private array $sets = [];
    private ?FilterExpr $filter = null;
    private ?Provenance $provenance = null;

    /**
     * Set the collection to update
     */
    public function collection(string $collection): self
    {
        $this->collection = $collection;
        return $this;
    }

    /**
     * Add a SET clause
     */
    public function set(string $field, mixed $value): self
    {
        $this->sets[$field] = $value;
        return $this;
    }

    /**
     * Add a WHERE filter
     */
    public function where(FilterExpr $filter): self
    {
        if ($this->filter === null) {
            $this->filter = $filter;
        } else {
            $this->filter = new AndFilter($this->filter, $filter);
        }
        return $this;
    }

    /**
     * Add provenance metadata
     */
    public function withProvenance(string|Provenance $actorOrProvenance, ?string $rationale = null): self
    {
        if ($actorOrProvenance instanceof Provenance) {
            $this->provenance = $actorOrProvenance;
        } else {
            $this->provenance = new Provenance($actorOrProvenance, $rationale ?? '');
        }
        return $this;
    }

    /**
     * Build the FDQL update string
     */
    public function toFdql(): string
    {
        if ($this->collection === null) {
            throw new \RuntimeException('Collection is required');
        }
        if (empty($this->sets)) {
            throw new \RuntimeException('At least one SET clause is required');
        }

        $setClauses = [];
        foreach ($this->sets as $field => $value) {
            $valueStr = match (true) {
                is_string($value) => '"' . addslashes($value) . '"',
                is_bool($value) => $value ? 'true' : 'false',
                is_null($value) => 'null',
                default => (string) $value,
            };
            $setClauses[] = "{$field} = {$valueStr}";
        }

        $query = "UPDATE {$this->collection} SET " . implode(', ', $setClauses);

        if ($this->filter !== null) {
            $query .= ' WHERE ' . $this->filter->toFdql();
        }

        if ($this->provenance !== null) {
            $query .= ' WITH PROVENANCE { actor: "' . addslashes($this->provenance->actor) . '", rationale: "' . addslashes($this->provenance->rationale) . '" }';
        }

        return $query;
    }

    public function getProvenance(): ?Provenance
    {
        return $this->provenance;
    }
}

/**
 * Fluent builder for DELETE statements
 */
final class DeleteBuilder
{
    private ?string $collection = null;
    private ?FilterExpr $filter = null;
    private ?Provenance $provenance = null;

    /**
     * Set the collection to delete from
     */
    public function from(string $collection): self
    {
        $this->collection = $collection;
        return $this;
    }

    /**
     * Add a WHERE filter
     */
    public function where(FilterExpr $filter): self
    {
        if ($this->filter === null) {
            $this->filter = $filter;
        } else {
            $this->filter = new AndFilter($this->filter, $filter);
        }
        return $this;
    }

    /**
     * Add provenance metadata
     */
    public function withProvenance(string|Provenance $actorOrProvenance, ?string $rationale = null): self
    {
        if ($actorOrProvenance instanceof Provenance) {
            $this->provenance = $actorOrProvenance;
        } else {
            $this->provenance = new Provenance($actorOrProvenance, $rationale ?? '');
        }
        return $this;
    }

    /**
     * Build the FDQL delete string
     */
    public function toFdql(): string
    {
        if ($this->collection === null) {
            throw new \RuntimeException('Collection is required');
        }

        $query = "DELETE FROM {$this->collection}";

        if ($this->filter !== null) {
            $query .= ' WHERE ' . $this->filter->toFdql();
        }

        if ($this->provenance !== null) {
            $query .= ' WITH PROVENANCE { actor: "' . addslashes($this->provenance->actor) . '", rationale: "' . addslashes($this->provenance->rationale) . '" }';
        }

        return $query;
    }

    public function getProvenance(): ?Provenance
    {
        return $this->provenance;
    }
}
