# VoID (Vocabulary of Interlinked Datasets) Setup

## What is VoID?

VoID is an RDF vocabulary for expressing metadata about RDF datasets. It helps:
- Discover datasets
- Understand dataset structure
- Find linked data connections
- Enable SPARQL endpoints
- Interoperate with semantic web tools

## Why VoID for verisimdb?

VoID enables verisimdb.dev to:
1. **Publish structured data** as Linked Open Data
2. **Connect to other datasets** (DBpedia, Wikidata, Schema.org)
3. **Enable semantic queries** via SPARQL
4. **Improve discoverability** in semantic web search engines
5. **Support research** and data integration

## VoID Files

- `.well-known/void.ttl` - Turtle format (human-readable)
- `.well-known/void.rdf` - RDF/XML format (tool-compatible)

## Accessing VoID Metadata

```bash
# Turtle format
curl https://verisimdb.dev/.well-known/void.ttl

# RDF/XML format
curl https://verisimdb.dev/.well-known/void.rdf
```

## Example: Querying with SPARQL

```sparql
PREFIX void: <http://rdfs.org/ns/void#>
PREFIX dcterms: <http://purl.org/dc/terms/>

SELECT ?dataset ?title ?triples
WHERE {
  ?dataset a void:Dataset ;
           dcterms:title ?title ;
           void:triples ?triples .
}
```

## Integration with verisimdb

VoID is **perfect** for verisimdb because:

1. **Semantic Database**: verisimdb can expose its data as RDF
2. **Linksets**: Connect verisimdb entities to external datasets
3. **SPARQL Endpoint**: Query verisimdb using SPARQL
4. **Schema Alignment**: Map verisimdb schema to standard ontologies

### Example verisimdb Integration

```turtle
# verisimdb dataset with linksets
<https://verisimdb.example.com/dataset> a void:Dataset ;
    dcterms:title "VerisimDB Verified Data" ;
    void:triples 1000000 ;
    void:entities 50000 ;

    # Link to DBpedia
    void:subset <https://verisimdb.example.com/linkset/dbpedia> ;

    # Link to Wikidata
    void:subset <https://verisimdb.example.com/linkset/wikidata> ;

    # SPARQL endpoint
    void:sparqlEndpoint <https://verisimdb.example.com/sparql> ;
.

# Linkset to DBpedia
<https://verisimdb.example.com/linkset/dbpedia> a void:Linkset ;
    void:linkPredicate owl:sameAs ;
    void:target <https://verisimdb.example.com/dataset> ;
    void:target <http://dbpedia.org> ;
    void:triples 25000 ;
.
```

## Serving VoID via SSG

For static site generators (SSG), VoID files can be:

1. **Pre-generated** during build
2. **Served as static files** from .well-known/
3. **Content-negotiated** (Turtle for browsers, RDF/XML for tools)

### Example: ReScript SSG Integration

```rescript
// void-generator.res
let generateVoID = (dataset: Dataset.t) => {
  let ttl = `
@prefix void: <http://rdfs.org/ns/void#> .

<https://example.com/dataset> a void:Dataset ;
    void:triples ${Int.toString(dataset.tripleCount)} ;
    void:entities ${Int.toString(dataset.entityCount)} .
`
  // Write to .well-known/void.ttl
  Node.Fs.writeFileSync(".well-known/void.ttl", ttl)
}
```

## Linking to External Datasets

### DBpedia

```turtle
void:subset [
    a void:Linkset ;
    void:linkPredicate owl:sameAs ;
    void:target <http://dbpedia.org> ;
    void:exampleResource <https://verisimdb.dev/entity/example> ;
] .
```

### Wikidata

```turtle
void:subset [
    a void:Linkset ;
    void:linkPredicate owl:sameAs ;
    void:target <https://www.wikidata.org/> ;
    void:exampleResource <https://verisimdb.dev/entity/example> ;
] .
```

### Schema.org

```turtle
void:vocabulary <https://schema.org/> ;
void:vocabularyPartition [
    void:class schema:Person ;
    void:entities 1000 ;
] .
```

## SPARQL Endpoint (Future)

To add a SPARQL endpoint:

1. **Cloudflare Worker** can proxy SPARQL queries
2. **GitHub Pages** can serve static SPARQL results
3. **Dedicated backend** (for dynamic queries)

```javascript
// sparql-worker.js (Cloudflare Worker)
addEventListener('fetch', event => {
  event.respondWith(handleSPARQL(event.request))
})

async function handleSPARQL(request) {
  const query = await request.text()
  // Parse SPARQL query
  // Execute against RDF store
  // Return results as JSON-LD or Turtle
}
```

## Validation

Validate VoID files:

```bash
# Using rapper (RDF parser)
rapper -i turtle .well-known/void.ttl

# Using Apache Jena
riot --validate .well-known/void.ttl
```

## Discovery

VoID metadata is discoverable via:
- **SPARQL endpoints**: `https://verisimdb.dev/sparql`
- **.well-known/**: `https://verisimdb.dev/.well-known/void.ttl`
- **HTTP Headers**: `Link: </.well-known/void.ttl>; rel="meta"`
- **HTML `<link>`**: `<link rel="meta" href="/.well-known/void.ttl">`

## Next Steps for verisimdb

1. **Export verisimdb data as RDF** (Turtle, N-Triples, RDF/XML)
2. **Update VoID statistics** (triple count, entities, etc.)
3. **Create linksets** to DBpedia, Wikidata, Schema.org
4. **Deploy SPARQL endpoint** (Cloudflare Worker or dedicated server)
5. **Add content negotiation** (serve different formats based on Accept header)

## Resources

- VoID Specification: https://www.w3.org/TR/void/
- VoID Guide: https://semanticweb.org/wiki/VoID
- LOD Cloud: https://lod-cloud.net/
- Linked Data: https://www.w3.org/DesignIssues/LinkedData.html

## License

PMPL-1.0-or-later
