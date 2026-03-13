# Lith Directus Extension

Directus extension for synchronizing content with Lith.

## Features

- **Real-time Sync** - Automatic sync on content changes
- **Collection Filtering** - Choose which collections to sync
- **System Collection Exclusion** - Automatically excludes `directus_*` collections
- **Audit Trail** - Full provenance tracking via Lith

## Installation

```bash
# In your Directus project
npm install @lith/directus-extension

# Or copy to extensions folder
cp -r dist/* extensions/hooks/lith/
```

## Configuration

Set environment variables:

```bash
# Required
LITH_URL=http://localhost:8080

# Optional
LITH_API_KEY=your-api-key
LITH_SYNC_COLLECTIONS=articles,authors,categories  # Comma-separated, empty = sync all
```

## Usage

### Automatic Sync

Once configured, the extension automatically syncs content:

```javascript
// When you create an item in Directus
await directus.items('articles').createOne({
  title: 'My Article',
  content: 'Article content...',
});
// -> Automatically synced to Lith 'articles' collection
```

### Supported Events

| Event | Action |
|-------|--------|
| `items.create` | Insert into Lith |
| `items.update` | Update in Lith |
| `items.delete` | Delete from Lith |

### Collection Filtering

By default, all non-system collections are synced. To limit sync:

```bash
# Only sync specific collections
LITH_SYNC_COLLECTIONS=articles,products,orders
```

System collections (`directus_*`) are always excluded.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LITH_URL` | Lith server URL | `http://localhost:8080` |
| `LITH_API_KEY` | API key for authentication | None |
| `LITH_SYNC_COLLECTIONS` | Collections to sync (comma-separated) | All non-system |

## Architecture

```
src/
├── Lith_Directus_Types.res  # Type definitions
└── Lith_Directus_Hook.res   # Hook extension
```

## Directus Extension Types

This package provides:

- **Hook Extension** - For action/filter events
- Can be extended to include:
  - **Endpoint Extension** - Custom API endpoints
  - **Panel Extension** - Admin panel widgets

## Development

```bash
# Build extension
npm run build

# Watch mode
npm run dev

# Test
npm test
```

## Provenance

All synced content includes provenance metadata:

```json
{
  "actor": "directus-extension",
  "rationale": "Auto-sync from Directus items.create",
  "source": "directus",
  "collection": "articles"
}
```

## Troubleshooting

### Connection Issues

```bash
# Check Lith is running
curl http://localhost:8080/v1/health

# Check environment variables
echo $LITH_URL
```

### Sync Not Working

1. Check collection is in `LITH_SYNC_COLLECTIONS` (or variable is unset)
2. Verify collection doesn't start with `directus_`
3. Check Directus logs for errors

### Performance

For high-volume sync, consider:
- Using batch sync mode
- Implementing debouncing for rapid updates
- Setting up Lith connection pooling

## License

PMPL-1.0-or-later
