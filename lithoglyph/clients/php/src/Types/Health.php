<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith\Types;

/**
 * Health status
 */
enum HealthStatus: string
{
    case HEALTHY = 'HEALTHY';
    case DEGRADED = 'DEGRADED';
    case UNHEALTHY = 'UNHEALTHY';
}

/**
 * Health response
 */
final class HealthResponse
{
    public function __construct(
        public readonly HealthStatus $status,
        public readonly string $version,
        public readonly int $uptimeSeconds,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            status: HealthStatus::tryFrom($data['status'] ?? 'UNHEALTHY') ?? HealthStatus::UNHEALTHY,
            version: $data['version'] ?? '',
            uptimeSeconds: (int) ($data['uptimeSeconds'] ?? 0),
        );
    }
}
