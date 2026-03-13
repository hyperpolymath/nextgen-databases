# Lith Strapi Plugin

Strapi plugin for synchronizing content with Lith.

## Features

- **Bidirectional Sync** - Sync content between Strapi and Lith
- **Selective Sync** - Choose which content types to sync
- **Lifecycle Hooks** - Automatic sync on create, update, delete
- **Audit Trail** - Full provenance tracking via Lith

## Installation

```bash
# In your Strapi project
npm install @lith/strapi-plugin
```

## Configuration

Add to `config/plugins.js`:

```javascript
module.exports = {
  lith: {
    enabled: true,
    config: {
      lithUrl: process.env.LITH_URL || 'http://localhost:8080',
      apiKey: process.env.LITH_API_KEY,
      collections: [
        {
          strapiModel: 'article',
          lithCollection: 'articles',
          syncMode: 'bidirectional', // or 'strapi-to-lith', 'lith-to-strapi'
        },
        {
          strapiModel: 'author',
          lithCollection: 'authors',
          syncMode: 'strapi-to-lith',
        },
      ],
    },
  },
};
```

## Sync Modes

| Mode | Description |
|------|-------------|
| `bidirectional` | Sync changes both ways (default) |
| `strapi-to-lith` | Only sync Strapi changes to Lith |
| `lith-to-strapi` | Only sync Lith changes to Strapi |

## Usage

### Automatic Sync

Once configured, the plugin automatically syncs content:

```javascript
// When you create an article in Strapi
const article = await strapi.entityService.create('api::article.article', {
  data: {
    title: 'My Article',
    content: 'Article content...',
  },
});
// -> Automatically synced to Lith 'articles' collection
```

### Manual Queries

Access Lith directly through the plugin service:

```javascript
// In a controller or service
const lithService = strapi.plugin('lith').service('sync');

// Query Lith
const articles = await lithService.queryLith('article', {
  where: 'status = "published"',
  limit: 10,
});

// Check Lith health
const health = await lithService.checkHealth();
```

### Lifecycle Hooks

The plugin registers these lifecycle hooks automatically:

- `afterCreate` - Sync new content to Lith
- `afterUpdate` - Sync updated content to Lith
- `afterDelete` - Remove content from Lith

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LITH_URL` | Lith server URL | `http://localhost:8080` |
| `LITH_API_KEY` | API key for authentication | None |

## API Endpoints

The plugin adds these admin API endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/lith/health` | GET | Check Lith connection |
| `/lith/sync/:model` | POST | Trigger manual sync for model |
| `/lith/query/:model` | GET | Query Lith collection |

## Provenance

All synced content includes provenance metadata:

```json
{
  "actor": "strapi-plugin",
  "rationale": "Auto-sync from Strapi create event",
  "source": "strapi",
  "model": "article",
  "action": "create"
}
```

## Development

```bash
# Build plugin
npm run build

# Run tests
npm test

# Watch mode
npm run dev
```

## Architecture

```
src/
├── Lith_Strapi_Types.res      # Type definitions
├── Lith_Strapi_Client.res     # HTTP client for Lith
├── Lith_Strapi_Service.res    # Sync service logic
├── Lith_Strapi_Plugin.res     # Main plugin entry
└── Lith_Strapi_Lifecycles.res # Strapi lifecycle hooks
```

## License

PMPL-1.0-or-later
