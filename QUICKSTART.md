# Glyphbase Quick Start

**Get up and running with Glyphbase in 5 minutes.**

## Prerequisites

- [Gleam](https://gleam.run) 1.0+
- [Lithoglyph](https://github.com/hyperpolymath/lithoglyph) database
- Erlang/OTP 26+

## Installation

```bash
# 1. Clone Glyphbase
git clone https://github.com/hyperpolymath/glyphbase
cd glyphbase/server

# 2. Install dependencies
gleam deps download

# 3. Start the server
gleam run

# 4. Open your browser
open http://localhost:4000
```

## Your First Table

1. Click **"+ New Table"**
2. Choose the **"Task Tracker"** template
3. Add a few tasks
4. Try different views: Grid → Kanban → Calendar
5. Click any cell to see its full provenance history

## Import Example Data

Load pre-made examples:

```bash
# Task tracker
curl -X POST http://localhost:4000/api/import \
  -H "Content-Type: application/json" \
  -d @examples/task-tracker.json

# Research papers
curl -X POST http://localhost:4000/api/import \
  -H "Content-Type: application/json" \
  -d @examples/research-papers.json
```

## Key Features to Try

### 1. Provenance (Time Travel)
- Right-click any cell → **"View History"**
- See every change with who/when/why
- Click any point to restore

### 2. PROMPT Scores
- Open the "Research Papers" table
- See quality scores for each paper
- Filter by `prompt_total >= 80` for high-quality papers only

### 3. Multiple Views
- **Grid**: Traditional spreadsheet
- **Kanban**: Drag tasks across status columns
- **Calendar**: See tasks by due date
- **Gallery**: Visual cards with images

### 4. Real-time Collaboration
- Open the same table in two browser windows
- Edit in one window → see live updates in the other
- No conflicts, ever (append-only journal)

## Next Steps

- Read the [User Guide](docs/USER-GUIDE.adoc)
- Explore the [API documentation](https://docs.lithoglyph.org/api)
- Join the [community discussions](https://github.com/hyperpolymath/glyphbase/discussions)

## Self-Hosting

Deploy Glyphbase on your own infrastructure:

### Docker

```bash
docker pull ghcr.io/hyperpolymath/glyphbase:latest
docker run -p 4000:4000 -v ./data:/data glyphbase
```

### From Source

```bash
git clone https://github.com/hyperpolymath/glyphbase
cd glyphbase/server
gleam run
```

## Getting Help

- 📖 [Full Documentation](https://docs.lithoglyph.org)
- 💬 [Community](https://github.com/hyperpolymath/glyphbase/discussions)
- 🐛 [Report Issues](https://github.com/hyperpolymath/glyphbase/issues)
- ✉️ support@lithoglyph.org

---

**Welcome to Glyphbase!** Carve your data in stone. 🪨
