# lith/lith-php

PHP client for Lith - the narrative-first, reversible, audit-grade database.

## Requirements

- PHP 8.1 or higher
- PSR-18 HTTP Client (e.g., Guzzle)
- PSR-17 HTTP Factories

## Installation

```bash
composer require lith/lith-php
```

## Quick Start

```php
<?php

use Lith\LithClient;
use Lith\Types\Provenance;
use GuzzleHttp\Client;
use GuzzleHttp\Psr7\HttpFactory;

// Create HTTP client and factories (using Guzzle)
$httpClient = new Client();
$httpFactory = new HttpFactory();

// Create Lith client
$lith = new LithClient(
    'http://localhost:8080',
    $httpClient,
    $httpFactory,
    $httpFactory
);

// Or from environment
$lith = LithClient::fromEnv($httpClient, $httpFactory, $httpFactory);

// Check health
$health = $lith->health();
echo "Server is " . $health->status->value . "\n";
```

## Query Examples

### Using Query Builder

```php
use Lith\Query\CompareOp;

// Build a SELECT query
$result = $lith->queryWith(
    $lith->select()
        ->from('articles')
        ->select(['id', 'title', 'author'])
        ->whereField('status', CompareOp::EQ, 'published')
        ->whereField('views', CompareOp::GT, 100)
        ->orderBy('createdAt', ascending: false)
        ->limit(10)
        ->withProvenance('editor@news.org', 'Daily review of popular articles')
);

foreach ($result->rows as $row) {
    echo $row['title'] . "\n";
}
```

### Raw GQL

```php
$result = $lith->query(
    'SELECT * FROM articles WHERE status = "published" LIMIT 10',
    new Provenance('editor@news.org', 'Daily review')
);

echo "Found {$result->rowCount} articles\n";
```

### Insert

```php
$result = $lith->insertWith(
    $lith->insert()
        ->into('articles')
        ->values([
            'title' => 'Breaking News',
            'author' => 'reporter@news.org',
            'content' => '...',
        ])
        ->withProvenance('reporter@news.org', 'New article submission')
);
```

### Update

```php
use Lith\Query\FieldFilter;
use Lith\Query\CompareOp;

$result = $lith->updateWith(
    $lith->update()
        ->collection('articles')
        ->set('status', 'archived')
        ->where(new FieldFilter('createdAt', CompareOp::LT, '2025-01-01'))
        ->withProvenance('admin@news.org', 'Archive old articles')
);
```

### Delete

```php
$result = $lith->deleteWith(
    $lith->delete()
        ->from('drafts')
        ->where(new FieldFilter('status', CompareOp::EQ, 'abandoned'))
        ->withProvenance('cleanup@news.org', 'Remove abandoned drafts')
);
```

## Collection Operations

```php
use Lith\Types\CollectionType;

// List collections
$collections = $lith->listCollections();
foreach ($collections as $col) {
    echo "{$col->name}: {$col->documentCount} documents\n";
}

// Create collection
$newCol = $lith->createCollection(
    'users',
    CollectionType::DOCUMENT,
    [
        'type' => 'object',
        'properties' => [
            'email' => ['type' => 'string'],
            'name' => ['type' => 'string'],
        ],
    ]
);

// Get collection
$col = $lith->getCollection('articles');

// Delete collection
$lith->deleteCollection('temp_data');
```

## Journal Operations

```php
// Get recent journal entries
$entries = $lith->getJournal(
    since: 1000,
    limit: 50,
    collection: 'articles'
);

foreach ($entries as $entry) {
    echo "[{$entry->seq}] {$entry->operation->value} on {$entry->collection}\n";
}
```

## Normalization

```php
use Lith\Types\NormalForm;

// Discover functional dependencies
$fds = $lith->discoverDependencies('orders', confidence: 0.95);

foreach ($fds as $fd) {
    $det = implode(', ', $fd->determinant);
    echo "{$det} -> {$fd->dependent} ({$fd->confidence->value})\n";
}

// Analyze normal form
$analysis = $lith->analyzeNormalForm('orders');

echo "Current: {$analysis->currentForm->value}, Target: {$analysis->targetForm->value}\n";

foreach ($analysis->violations as $violation) {
    echo "Violation: {$violation}\n";
}

foreach ($analysis->recommendations as $rec) {
    echo "Recommendation: {$rec}\n";
}
```

## Migration

```php
// Start migration to BCNF
$migration = $lith->startMigration('orders', NormalForm::BCNF);

echo "Migration {$migration->id} started: {$migration->narrative}\n";

// When ready, commit
$lith->commitMigration($migration->id);
```

## Authentication

```php
// API Key
$lith = new LithClient('http://localhost:8080', $httpClient, $httpFactory, $httpFactory);
$lith->setApiKey('your-api-key');

// Bearer Token (JWT)
$lith->setBearerToken('your-jwt-token');
```

## Filter Expressions

The query builder supports complex filter expressions:

```php
use Lith\Query\FieldFilter;
use Lith\Query\AndFilter;
use Lith\Query\OrFilter;
use Lith\Query\NotFilter;
use Lith\Query\CompareOp;

// Simple comparison
$filter = new FieldFilter('status', CompareOp::EQ, 'active');

// AND
$filter = new AndFilter(
    new FieldFilter('status', CompareOp::EQ, 'active'),
    new FieldFilter('views', CompareOp::GT, 100)
);

// OR
$filter = new OrFilter(
    new FieldFilter('priority', CompareOp::EQ, 'high'),
    new FieldFilter('urgent', CompareOp::EQ, true)
);

// NOT
$filter = new NotFilter(new FieldFilter('deleted', CompareOp::EQ, true));

// Complex nested
$filter = new AndFilter(
    new FieldFilter('status', CompareOp::EQ, 'published'),
    new OrFilter(
        new FieldFilter('category', CompareOp::EQ, 'news'),
        new FieldFilter('featured', CompareOp::EQ, true)
    )
);

// Use in query
$result = $lith->queryWith(
    $lith->select()
        ->from('articles')
        ->where($filter)
);
```

## Error Handling

All API methods throw `LithException` on error:

```php
use Lith\LithException;

try {
    $result = $lith->query('SELECT * FROM articles');
} catch (LithException $e) {
    echo "Error {$e->code}: {$e->getMessage()}\n";
    if ($e->details) {
        print_r($e->details);
    }
}
```

## Laravel Integration

```php
// config/services.php
return [
    'lith' => [
        'url' => env('LITH_URL', 'http://localhost:8080'),
        'api_key' => env('LITH_API_KEY'),
    ],
];

// app/Providers/AppServiceProvider.php
use Lith\LithClient;
use GuzzleHttp\Client;
use GuzzleHttp\Psr7\HttpFactory;

public function register(): void
{
    $this->app->singleton(LithClient::class, function ($app) {
        $httpClient = new Client();
        $httpFactory = new HttpFactory();

        $client = new LithClient(
            config('services.lith.url'),
            $httpClient,
            $httpFactory,
            $httpFactory
        );

        if ($apiKey = config('services.lith.api_key')) {
            $client->setApiKey($apiKey);
        }

        return $client;
    });
}

// In a controller
public function index(LithClient $lith)
{
    $articles = $lith->queryWith(
        $lith->select()
            ->from('articles')
            ->whereField('status', '=', 'published')
            ->limit(10)
    );

    return view('articles.index', ['articles' => $articles->rows]);
}
```

## Symfony Integration

```yaml
# config/services.yaml
services:
    GuzzleHttp\Client: ~
    GuzzleHttp\Psr7\HttpFactory: ~

    Lith\LithClient:
        arguments:
            $baseUrl: '%env(LITH_URL)%'
            $httpClient: '@GuzzleHttp\Client'
            $requestFactory: '@GuzzleHttp\Psr7\HttpFactory'
            $streamFactory: '@GuzzleHttp\Psr7\HttpFactory'
        calls:
            - setApiKey: ['%env(LITH_API_KEY)%']
```

## Types Reference

All types are in the `Lith\Types` namespace:

- `Provenance` - Audit trail metadata
- `QueryResult` - Query response
- `Collection` - Collection metadata
- `CollectionType` - Document/Edge/Schema enum
- `JournalEntry` - Journal entry
- `JournalOperation` - Operation type enum
- `FunctionalDependency` - Discovered FD
- `ConfidenceLevel` - High/Medium/Low enum
- `NormalForm` - 1NF/2NF/3NF/BCNF enum
- `NormalFormAnalysis` - NF analysis result
- `MigrationStatus` - Migration state
- `MigrationPhase` - Announce/Shadow/Commit/Rollback enum
- `HealthResponse` - Health check response
- `HealthStatus` - Healthy/Degraded/Unhealthy enum

## License

PMPL-1.0-or-later
