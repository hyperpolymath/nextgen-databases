<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

namespace Lith;

use Lith\Query\QueryBuilder;
use Lith\Query\InsertBuilder;
use Lith\Query\UpdateBuilder;
use Lith\Query\DeleteBuilder;
use Lith\Types\Collection;
use Lith\Types\CollectionType;
use Lith\Types\FunctionalDependency;
use Lith\Types\HealthResponse;
use Lith\Types\JournalEntry;
use Lith\Types\MigrationStatus;
use Lith\Types\NormalForm;
use Lith\Types\NormalFormAnalysis;
use Lith\Types\Provenance;
use Lith\Types\QueryResult;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;
use Psr\Http\Message\StreamFactoryInterface;

/**
 * Lith Exception
 */
class LithException extends \Exception
{
    public function __construct(
        string $message,
        public readonly string $code = '',
        public readonly ?array $details = null,
        ?\Throwable $previous = null
    ) {
        parent::__construct($message, 0, $previous);
    }
}

/**
 * Lith PHP Client
 *
 * Type-safe client for Lith REST API
 */
final class LithClient
{
    private string $baseUrl;
    private ?string $apiKey = null;
    private ?string $bearerToken = null;
    private ClientInterface $httpClient;
    private RequestFactoryInterface $requestFactory;
    private StreamFactoryInterface $streamFactory;

    public function __construct(
        string $baseUrl,
        ClientInterface $httpClient,
        RequestFactoryInterface $requestFactory,
        StreamFactoryInterface $streamFactory,
    ) {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->httpClient = $httpClient;
        $this->requestFactory = $requestFactory;
        $this->streamFactory = $streamFactory;
    }

    /**
     * Create client from environment variables
     */
    public static function fromEnv(
        ClientInterface $httpClient,
        RequestFactoryInterface $requestFactory,
        StreamFactoryInterface $streamFactory,
    ): self {
        $baseUrl = getenv('LITH_URL') ?: 'http://localhost:8080';
        $client = new self($baseUrl, $httpClient, $requestFactory, $streamFactory);

        if ($apiKey = getenv('LITH_API_KEY')) {
            $client->setApiKey($apiKey);
        }

        return $client;
    }

    /**
     * Set API key authentication
     */
    public function setApiKey(string $apiKey): self
    {
        $this->apiKey = $apiKey;
        $this->bearerToken = null;
        return $this;
    }

    /**
     * Set Bearer token authentication
     */
    public function setBearerToken(string $token): self
    {
        $this->bearerToken = $token;
        $this->apiKey = null;
        return $this;
    }

    // =========================================================================
    // Query Operations
    // =========================================================================

    /**
     * Execute an GQL query
     */
    public function query(string $gql, ?Provenance $provenance = null, bool $explain = false): QueryResult
    {
        $body = ['gql' => $gql];
        if ($provenance !== null) {
            $body['provenance'] = $provenance->toArray();
        }
        if ($explain) {
            $body['explain'] = true;
        }

        $response = $this->request('POST', '/v1/query', $body);
        return QueryResult::fromArray($response);
    }

    /**
     * Execute a query using the query builder
     */
    public function queryWith(QueryBuilder $builder): QueryResult
    {
        return $this->query($builder->toGql(), $builder->getProvenance());
    }

    /**
     * Create a new query builder
     */
    public function select(): QueryBuilder
    {
        return new QueryBuilder();
    }

    /**
     * Create a new insert builder
     */
    public function insert(): InsertBuilder
    {
        return new InsertBuilder();
    }

    /**
     * Create a new update builder
     */
    public function update(): UpdateBuilder
    {
        return new UpdateBuilder();
    }

    /**
     * Create a new delete builder
     */
    public function delete(): DeleteBuilder
    {
        return new DeleteBuilder();
    }

    /**
     * Execute an insert using the builder
     */
    public function insertWith(InsertBuilder $builder): QueryResult
    {
        return $this->query($builder->toGql(), $builder->getProvenance());
    }

    /**
     * Execute an update using the builder
     */
    public function updateWith(UpdateBuilder $builder): QueryResult
    {
        return $this->query($builder->toGql(), $builder->getProvenance());
    }

    /**
     * Execute a delete using the builder
     */
    public function deleteWith(DeleteBuilder $builder): QueryResult
    {
        return $this->query($builder->toGql(), $builder->getProvenance());
    }

    // =========================================================================
    // Collection Operations
    // =========================================================================

    /**
     * List all collections
     * @return Collection[]
     */
    public function listCollections(): array
    {
        $response = $this->request('GET', '/v1/collections');
        return array_map(fn($item) => Collection::fromArray($item), $response);
    }

    /**
     * Get a specific collection
     */
    public function getCollection(string $name): Collection
    {
        $response = $this->request('GET', "/v1/collections/{$name}");
        return Collection::fromArray($response);
    }

    /**
     * Create a new collection
     */
    public function createCollection(
        string $name,
        CollectionType $type = CollectionType::DOCUMENT,
        ?array $schema = null
    ): Collection {
        $body = [
            'name' => $name,
            'type' => $type->value,
        ];
        if ($schema !== null) {
            $body['schema'] = $schema;
        }

        $response = $this->request('POST', '/v1/collections', $body);
        return Collection::fromArray($response);
    }

    /**
     * Delete a collection
     */
    public function deleteCollection(string $name): void
    {
        $this->request('DELETE', "/v1/collections/{$name}");
    }

    // =========================================================================
    // Journal Operations
    // =========================================================================

    /**
     * Get journal entries
     * @return JournalEntry[]
     */
    public function getJournal(?int $since = null, ?int $limit = null, ?string $collection = null): array
    {
        $params = [];
        if ($since !== null) {
            $params['since'] = $since;
        }
        if ($limit !== null) {
            $params['limit'] = $limit;
        }
        if ($collection !== null) {
            $params['collection'] = $collection;
        }

        $queryStr = !empty($params) ? '?' . http_build_query($params) : '';
        $response = $this->request('GET', "/v1/journal{$queryStr}");

        return array_map(fn($item) => JournalEntry::fromArray($item), $response);
    }

    // =========================================================================
    // Normalization Operations
    // =========================================================================

    /**
     * Discover functional dependencies
     * @return FunctionalDependency[]
     */
    public function discoverDependencies(string $collection, ?float $confidence = null): array
    {
        $body = ['collection' => $collection];
        if ($confidence !== null) {
            $body['minConfidence'] = $confidence;
        }

        $response = $this->request('POST', '/v1/normalize/discover', $body);
        return array_map(fn($item) => FunctionalDependency::fromArray($item), $response);
    }

    /**
     * Analyze normal form
     */
    public function analyzeNormalForm(string $collection): NormalFormAnalysis
    {
        $response = $this->request('POST', '/v1/normalize/analyze', ['collection' => $collection]);
        return NormalFormAnalysis::fromArray($response);
    }

    // =========================================================================
    // Migration Operations
    // =========================================================================

    /**
     * Start a migration
     */
    public function startMigration(string $collection, NormalForm $targetForm): MigrationStatus
    {
        $response = $this->request('POST', '/v1/migrate/start', [
            'collection' => $collection,
            'targetForm' => $targetForm->value,
        ]);
        return MigrationStatus::fromArray($response);
    }

    /**
     * Commit a migration
     */
    public function commitMigration(string $migrationId): void
    {
        $this->request('POST', '/v1/migrate/commit', ['migrationId' => $migrationId]);
    }

    // =========================================================================
    // Health Check
    // =========================================================================

    /**
     * Check server health
     */
    public function health(): HealthResponse
    {
        $response = $this->request('GET', '/v1/health');
        return HealthResponse::fromArray($response);
    }

    // =========================================================================
    // Internal HTTP Methods
    // =========================================================================

    /**
     * Make an HTTP request
     * @return array<string, mixed>
     */
    private function request(string $method, string $path, ?array $body = null): array
    {
        $url = $this->baseUrl . $path;
        $request = $this->requestFactory->createRequest($method, $url);

        // Add headers
        $request = $request
            ->withHeader('Content-Type', 'application/json')
            ->withHeader('Accept', 'application/json');

        if ($this->apiKey !== null) {
            $request = $request->withHeader('X-API-Key', $this->apiKey);
        } elseif ($this->bearerToken !== null) {
            $request = $request->withHeader('Authorization', 'Bearer ' . $this->bearerToken);
        }

        // Add body
        if ($body !== null) {
            $jsonBody = json_encode($body, JSON_THROW_ON_ERROR);
            $stream = $this->streamFactory->createStream($jsonBody);
            $request = $request->withBody($stream);
        }

        // Send request
        $response = $this->httpClient->sendRequest($request);

        // Parse response
        $statusCode = $response->getStatusCode();
        $responseBody = (string) $response->getBody();

        if ($statusCode >= 400) {
            $errorData = json_decode($responseBody, true) ?: [];
            throw new LithException(
                $errorData['message'] ?? 'Request failed',
                (string) $statusCode,
                $errorData['details'] ?? null
            );
        }

        if ($responseBody === '') {
            return [];
        }

        return json_decode($responseBody, true, 512, JSON_THROW_ON_ERROR);
    }
}
