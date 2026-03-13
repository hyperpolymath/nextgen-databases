# Lith CMS Integrations

Official integrations for popular CMS platforms.

## Available Integrations

| CMS | Package | Type | Status |
|-----|---------|------|--------|
| Strapi | `@lith/strapi-plugin` | Plugin | Stable |
| Directus | `@lith/directus-extension` | Hook Extension | Stable |
| Ghost | `@lith/ghost-integration` | Webhook Server | Stable |
| Payload CMS | `@lith/payload-adapter` | Plugin | Stable |

## Quick Start

### Strapi

```javascript
// config/plugins.js
module.exports = {
  lith: {
    enabled: true,
    config: {
      lithUrl: process.env.LITH_URL,
      apiKey: process.env.LITH_API_KEY,
      collections: [
        { strapiModel: 'article', lithCollection: 'articles', syncMode: 'bidirectional' },
      ],
    },
  },
};
```

### Directus

```bash
# Set environment variables
LITH_URL=http://localhost:8080
LITH_API_KEY=your-api-key
LITH_SYNC_COLLECTIONS=articles,products
```

### Ghost

```bash
# Run webhook server
deno run --allow-net --allow-env @lith/ghost-integration

# Configure webhooks in Ghost Admin
# Point events to: http://your-server:3000/webhook
```

### Payload CMS

```typescript
// payload.config.ts
import lithPlugin from '@lith/payload-adapter';

export default buildConfig({
  plugins: [
    lithPlugin({
      lithUrl: process.env.LITH_URL,
      collections: [
        { payloadSlug: 'posts', lithCollection: 'posts', syncMode: 'bidirectional' },
      ],
    }),
  ],
});
```

## Sync Modes

All integrations support three sync modes:

| Mode | Description |
|------|-------------|
| `bidirectional` | Sync changes both ways |
| `cms-to-lith` | Only sync CMS changes to Lith |
| `lith-to-cms` | Only sync Lith changes to CMS |

## Features

### Common Features

- **Real-time Sync** - Automatic sync on content changes
- **Selective Sync** - Choose which content types to sync
- **Audit Trail** - Full provenance tracking in Lith
- **Error Handling** - Graceful failure with logging

### Lith Benefits

When you sync to Lith, you get:

- **Narrative History** - Every change has a reason
- **Reversibility** - Undo any change with full context
- **Audit Grade** - Meet compliance requirements
- **Normalization** - Auto-detect schema improvements
- **Multi-Protocol** - Query via REST, gRPC, or GraphQL

## Architecture

```
integrations/
├── README.md            # This file
├── strapi/              # Strapi v4/v5 plugin
│   ├── src/
│   │   ├── Lith_Strapi_Types.res
│   │   ├── Lith_Strapi_Client.res
│   │   ├── Lith_Strapi_Service.res
│   │   ├── Lith_Strapi_Plugin.res
│   │   └── Lith_Strapi_Lifecycles.res
│   └── README.md
├── directus/            # Directus hook extension
│   ├── src/
│   │   ├── Lith_Directus_Types.res
│   │   └── Lith_Directus_Hook.res
│   └── README.md
├── ghost/               # Ghost webhook server
│   ├── src/
│   │   ├── Lith_Ghost_Types.res
│   │   ├── Lith_Ghost_Webhook.res
│   │   └── Lith_Ghost_Server.res
│   └── README.md
└── payload/             # Payload CMS plugin
    ├── src/
    │   ├── Lith_Payload_Types.res
    │   ├── Lith_Payload_Hooks.res
    │   └── Lith_Payload_Plugin.res
    └── README.md
```

## Environment Variables

| Variable | Used By | Description |
|----------|---------|-------------|
| `LITH_URL` | All | Lith server URL |
| `LITH_API_KEY` | All | API key for authentication |
| `LITH_SYNC_COLLECTIONS` | Directus | Collections to sync (comma-separated) |
| `GHOST_WEBHOOK_SECRET` | Ghost | Webhook signature secret |
| `LITH_ENABLED` | Payload | Enable/disable plugin |

## Provenance Tracking

All integrations add provenance metadata:

```json
{
  "actor": "strapi-plugin",
  "rationale": "Auto-sync from Strapi create event",
  "source": "strapi",
  "model": "article",
  "action": "create",
  "timestamp": "2026-01-12T10:30:00Z"
}
```

## Development

All integrations are written in ReScript and compile to JavaScript:

```bash
# Build all integrations
cd integrations/strapi && npm run build
cd integrations/directus && npm run build
cd integrations/ghost && deno task build
cd integrations/payload && npm run build
```

## Contributing

See the main Lith repository for contribution guidelines.

## License

PMPL-1.0-or-later
