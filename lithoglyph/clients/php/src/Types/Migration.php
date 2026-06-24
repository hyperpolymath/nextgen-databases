<?php

declare(strict_types=1);

// SPDX-License-Identifier: MPL-2.0

namespace Lith\Types;

/**
 * Migration phase
 */
enum MigrationPhase: string
{
    case ANNOUNCE = 'ANNOUNCE';
    case SHADOW = 'SHADOW';
    case COMMIT = 'COMMIT';
    case ROLLBACK = 'ROLLBACK';
}

/**
 * Migration status
 */
final class MigrationStatus
{
    public function __construct(
        public readonly string $id,
        public readonly MigrationPhase $phase,
        public readonly string $collection,
        public readonly string $startedAt,
        public readonly string $narrative,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            id: $data['id'] ?? '',
            phase: MigrationPhase::tryFrom($data['phase'] ?? 'ANNOUNCE') ?? MigrationPhase::ANNOUNCE,
            collection: $data['collection'] ?? '',
            startedAt: $data['startedAt'] ?? '',
            narrative: $data['narrative'] ?? '',
        );
    }
}
