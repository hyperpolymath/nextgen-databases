# Lith Payload CMS Adapter

Payload CMS plugin for synchronizing content with Lith.

## Features

- **Real-time Sync** - Automatic sync on content changes
- **Selective Collections** - Choose which collections to sync
- **Field Exclusion** - Exclude sensitive fields from sync
- **Bidirectional Support** - Sync both ways or one-way

## Installation

```bash
npm install @lith/payload-adapter
```

## Configuration

Add to your `payload.config.ts`:

```typescript
import { buildConfig } from 'payload/config';
import lithPlugin from '@lith/payload-adapter';

export default buildConfig({
  plugins: [
    lithPlugin({
      lithUrl: process.env.LITH_URL || 'http://localhost:8080',
      apiKey: process.env.LITH_API_KEY,
      enabled: true,
      collections: [
        {
          payloadSlug: 'posts',
          lithCollection: 'posts',
          syncMode: 'bidirectional',
          excludeFields: ['_status', '__v'],
        },
        {
          payloadSlug: 'pages',
          lithCollection: 'pages',
          syncMode: 'payload-to-lith',
          excludeFields: [],
        },
      ],
    }),
  ],
  // ... rest of config
});
```

## Sync Modes

| Mode | Description |
|------|-------------|
| `bidirectional` | Sync changes both ways (default) |
| `payload-to-lith` | Only sync Payload changes to Lith |
| `lith-to-payload` | Only sync Lith changes to Payload |

## Usage

### Automatic Sync

Once configured, content syncs automatically:

```typescript
// Create a post in Payload
await payload.create({
  collection: 'posts',
  data: {
    title: 'My Post',
    content: 'Post content...',
  },
});
// -> Automatically synced to Lith 'posts' collection
```

### Field Exclusion

Exclude fields from sync:

```typescript
{
  payloadSlug: 'users',
  lithCollection: 'users',
  syncMode: 'payload-to-lith',
  excludeFields: ['password', 'resetPasswordToken', '_verified'],
}
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LITH_URL` | Lith server URL | `http://localhost:8080` |
| `LITH_API_KEY` | API key for authentication | None |
| `LITH_ENABLED` | Enable/disable plugin | `true` |

## Hooks

The plugin adds these hooks to synced collections:

| Hook | Trigger |
|------|---------|
| `afterChange` | After create or update |
| `afterDelete` | After delete |

## Architecture

```
src/
├── Lith_Payload_Types.res   # Type definitions
├── Lith_Payload_Hooks.res   # Collection hooks
└── Lith_Payload_Plugin.res  # Plugin entry point
```

## Provenance

All synced content includes provenance metadata:

```json
{
  "actor": "payload-adapter",
  "rationale": "Auto-sync from Payload afterChange hook",
  "source": "payload",
  "collection": "posts",
  "operation": "create"
}
```

## Local Fields

Payload's `localized` fields are synced as nested objects:

```json
{
  "id": "123",
  "title": {
    "en": "English Title",
    "de": "German Title"
  }
}
```

## Development

```bash
# Build
npm run build

# Test
npm test
```

## TypeScript Support

Type definitions are included:

```typescript
import type { PluginConfig, CollectionMapping, SyncMode } from '@lith/payload-adapter';

const config: PluginConfig = {
  lithUrl: 'http://localhost:8080',
  enabled: true,
  collections: [],
};
```

## License

PMPL-1.0-or-later
