<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith\Types;

/**
 * Collection type enum
 */
enum CollectionType: string
{
    case DOCUMENT = 'DOCUMENT';
    case EDGE = 'EDGE';
    case SCHEMA = 'SCHEMA';
}

/**
 * Collection metadata
 */
final class Collection
{
    public function __construct(
        public readonly string $name,
        public readonly CollectionType $type,
        public readonly int $documentCount,
        public readonly ?array $schema = null,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            name: $data['name'] ?? '',
            type: CollectionType::tryFrom($data['type'] ?? 'DOCUMENT') ?? CollectionType::DOCUMENT,
            documentCount: (int) ($data['documentCount'] ?? 0),
            schema: $data['schema'] ?? null,
        );
    }
}
