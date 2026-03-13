<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith\Types;

/**
 * Provenance metadata for audit trail
 */
final class Provenance implements \JsonSerializable
{
    public function __construct(
        public readonly string $actor,
        public readonly string $rationale,
        public readonly ?string $timestamp = null,
        public readonly ?string $source = null,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            actor: $data['actor'] ?? '',
            rationale: $data['rationale'] ?? '',
            timestamp: $data['timestamp'] ?? null,
            source: $data['source'] ?? null,
        );
    }

    public function toArray(): array
    {
        return array_filter([
            'actor' => $this->actor,
            'rationale' => $this->rationale,
            'timestamp' => $this->timestamp,
            'source' => $this->source,
        ], fn($v) => $v !== null);
    }

    public function jsonSerialize(): array
    {
        return $this->toArray();
    }
}
