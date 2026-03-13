<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith\Types;

/**
 * Journal operation type
 */
enum JournalOperation: string
{
    case INSERT = 'INSERT';
    case UPDATE = 'UPDATE';
    case DELETE = 'DELETE';
    case CREATE_COLLECTION = 'CREATE_COLLECTION';
    case DROP_COLLECTION = 'DROP_COLLECTION';
    case MIGRATION_START = 'MIGRATION_START';
    case MIGRATION_COMMIT = 'MIGRATION_COMMIT';
}

/**
 * Journal entry
 */
final class JournalEntry
{
    public function __construct(
        public readonly int $seq,
        public readonly string $timestamp,
        public readonly JournalOperation $operation,
        public readonly ?string $collection = null,
        public readonly ?string $documentId = null,
        public readonly ?Provenance $provenance = null,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            seq: (int) ($data['seq'] ?? 0),
            timestamp: $data['timestamp'] ?? '',
            operation: JournalOperation::tryFrom($data['operation'] ?? 'INSERT') ?? JournalOperation::INSERT,
            collection: $data['collection'] ?? null,
            documentId: $data['documentId'] ?? null,
            provenance: isset($data['provenance']) ? Provenance::fromArray($data['provenance']) : null,
        );
    }
}
