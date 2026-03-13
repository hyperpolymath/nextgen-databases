<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith\Types;

/**
 * Query result
 */
final class QueryResult
{
    /**
     * @param array<int, array<string, mixed>> $rows
     */
    public function __construct(
        public readonly array $rows,
        public readonly int $rowCount,
        public readonly int $journalSeq,
        public readonly ?Provenance $provenance = null,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            rows: $data['rows'] ?? [],
            rowCount: (int) ($data['rowCount'] ?? 0),
            journalSeq: (int) ($data['journalSeq'] ?? 0),
            provenance: isset($data['provenance']) ? Provenance::fromArray($data['provenance']) : null,
        );
    }
}
