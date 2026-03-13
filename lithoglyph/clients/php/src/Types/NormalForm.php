<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith\Types;

/**
 * Normal form level
 */
enum NormalForm: string
{
    case NF1 = '1NF';
    case NF2 = '2NF';
    case NF3 = '3NF';
    case BCNF = 'BCNF';
}

/**
 * Confidence level for discovered dependencies
 */
enum ConfidenceLevel: string
{
    case HIGH = 'HIGH';
    case MEDIUM = 'MEDIUM';
    case LOW = 'LOW';
}

/**
 * Functional dependency
 */
final class FunctionalDependency
{
    /**
     * @param string[] $determinant
     */
    public function __construct(
        public readonly array $determinant,
        public readonly string $dependent,
        public readonly ConfidenceLevel $confidence,
        public readonly int $sampleSize,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            determinant: $data['determinant'] ?? [],
            dependent: $data['dependent'] ?? '',
            confidence: ConfidenceLevel::tryFrom($data['confidence'] ?? 'MEDIUM') ?? ConfidenceLevel::MEDIUM,
            sampleSize: (int) ($data['sampleSize'] ?? 0),
        );
    }
}

/**
 * Normal form analysis result
 */
final class NormalFormAnalysis
{
    /**
     * @param string[] $violations
     * @param string[] $recommendations
     */
    public function __construct(
        public readonly NormalForm $currentForm,
        public readonly NormalForm $targetForm,
        public readonly array $violations,
        public readonly array $recommendations,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            currentForm: NormalForm::tryFrom($data['currentForm'] ?? '1NF') ?? NormalForm::NF1,
            targetForm: NormalForm::tryFrom($data['targetForm'] ?? 'BCNF') ?? NormalForm::BCNF,
            violations: $data['violations'] ?? [],
            recommendations: $data['recommendations'] ?? [],
        );
    }
}
