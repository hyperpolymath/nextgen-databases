# Lith Client Libraries

Official client libraries for Lith - the narrative-first, reversible, audit-grade database.

## Available Clients

| Language | Package | Status | Features |
|----------|---------|--------|----------|
| ReScript | `@lith/rescript` | Stable | Type-safe, Deno runtime |
| PHP | `lith/lith-php` | Stable | PSR-18, Laravel/Symfony |

## Quick Start

### ReScript (Deno)

```rescript
open Lith
open Lith_Types

let client = make(~baseUrl="http://localhost:8080")

// Query with fluent builder
let result = await client->queryWith(
  select()
  ->from("articles")
  ->whereField("status", Eq, "published")
  ->limit(10)
  ->withProvenance("user@example.com", "List articles")
)

result.rows->Array.forEach(row => Console.log(row))
```

### PHP

```php
use Lith\LithClient;
use Lith\Query\CompareOp;

$client = LithClient::fromEnv($httpClient, $httpFactory, $httpFactory);

$result = $client->queryWith(
    $client->select()
        ->from('articles')
        ->whereField('status', CompareOp::EQ, 'published')
        ->limit(10)
        ->withProvenance('user@example.com', 'List articles')
);

foreach ($result->rows as $row) {
    echo $row['title'] . "\n";
}
```

## Features

All clients support:

- **FDQL Queries** - Full query language support
- **Query Builder** - Type-safe, fluent query construction
- **Provenance** - Audit trail metadata on all operations
- **Collections** - List, create, delete collections
- **Journal** - Access audit log entries
- **Normalization** - Discover dependencies, analyze normal forms
- **Migration** - Start and commit schema migrations
- **Health** - Server health checks

## Authentication

```rescript
// ReScript - API Key
let client = make(~baseUrl="http://localhost:8080", ~apiKey="your-api-key")

// ReScript - Bearer Token
let client = make(~baseUrl="http://localhost:8080", ~bearerToken="your-jwt")

// ReScript - From Environment
let client = fromEnv() // Uses LITH_URL, LITH_API_KEY
```

```php
// PHP - API Key
$client->setApiKey('your-api-key');

// PHP - Bearer Token
$client->setBearerToken('your-jwt');

// PHP - From Environment
$client = LithClient::fromEnv(...); // Uses LITH_URL, LITH_API_KEY
```

## Query Builder

### SELECT

```rescript
// ReScript
select()
->from("users")
->select(["id", "name", "email"])
->whereField("active", Eq, true)
->whereField("created_at", Gt, "2025-01-01")
->orderBy("name", ~ascending=true)
->limit(100)
->offset(0)
```

```php
// PHP
$client->select()
    ->from('users')
    ->select(['id', 'name', 'email'])
    ->whereField('active', CompareOp::EQ, true)
    ->whereField('created_at', CompareOp::GT, '2025-01-01')
    ->orderBy('name', ascending: true)
    ->limit(100)
    ->offset(0);
```

### INSERT

```rescript
// ReScript
insert()
->into("users")
->values({"name": "Alice", "email": "alice@example.com"})
->withProvenance("admin", "Create user")
```

```php
// PHP
$client->insert()
    ->into('users')
    ->values(['name' => 'Alice', 'email' => 'alice@example.com'])
    ->withProvenance('admin', 'Create user');
```

### UPDATE

```rescript
// ReScript
update()
->collection("users")
->set("status", "inactive")
->where(Field("last_login", Lt, "2024-01-01"))
->withProvenance("cleanup-job", "Deactivate old users")
```

```php
// PHP
$client->update()
    ->collection('users')
    ->set('status', 'inactive')
    ->where(new FieldFilter('last_login', CompareOp::LT, '2024-01-01'))
    ->withProvenance('cleanup-job', 'Deactivate old users');
```

### DELETE

```rescript
// ReScript
delete()
->from("sessions")
->where(Field("expires_at", Lt, now()))
->withProvenance("session-cleanup", "Remove expired sessions")
```

```php
// PHP
$client->delete()
    ->from('sessions')
    ->where(new FieldFilter('expires_at', CompareOp::LT, $now))
    ->withProvenance('session-cleanup', 'Remove expired sessions');
```

## Filter Expressions

Complex filters with AND, OR, NOT:

```rescript
// ReScript
let filter = And(
  Field("status", Eq, "active"),
  Or(
    Field("role", Eq, "admin"),
    Field("role", Eq, "moderator")
  )
)

select()->from("users")->where(filter)
```

```php
// PHP
$filter = new AndFilter(
    new FieldFilter('status', CompareOp::EQ, 'active'),
    new OrFilter(
        new FieldFilter('role', CompareOp::EQ, 'admin'),
        new FieldFilter('role', CompareOp::EQ, 'moderator')
    )
);

$client->select()->from('users')->where($filter);
```

## Error Handling

```rescript
// ReScript
try {
  let result = await client->query("SELECT * FROM missing")
  // ... handle result
} catch {
| LithError(err) => Console.error(`Error: ${err.message}`)
}
```

```php
// PHP
try {
    $result = $client->query('SELECT * FROM missing');
} catch (LithException $e) {
    echo "Error {$e->code}: {$e->getMessage()}\n";
}
```

## Directory Structure

```
clients/
├── README.md           # This file
├── rescript/           # ReScript client
│   ├── src/
│   │   ├── Lith.res
│   │   ├── Lith_Types.res
│   │   └── Lith_Query.res
│   ├── rescript.json
│   └── deno.json
└── php/                # PHP client
    ├── src/
    │   ├── LithClient.php
    │   ├── Types/
    │   └── Query/
    ├── composer.json
    └── README.md
```

## SDK Generator

The `tools/sdk-gen/` directory contains a code generator that can produce basic client skeletons from the API specification. The hand-crafted clients in this directory provide better ergonomics and are recommended for production use.

## Contributing

See the main Lith repository for contribution guidelines.

## License

PMPL-1.0-or-later
