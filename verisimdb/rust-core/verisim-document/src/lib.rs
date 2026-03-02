// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Document Modality
//!
//! Full-text search via Tantivy.
//! Implements Marr's Computational Level: "What text matches?"

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tantivy::collector::TopDocs;
use tantivy::query::QueryParser;
use tantivy::schema::{Field, Schema, Value, STORED, TEXT};
use tantivy::snippet::SnippetGenerator;
use tantivy::{Index, IndexReader, IndexWriter, ReloadPolicy, TantivyDocument};
use thiserror::Error;
use tokio::sync::RwLock;

/// Document modality errors
#[derive(Error, Debug)]
pub enum DocumentError {
    #[error("Index error: {0}")]
    IndexError(String),

    #[error("Document not found: {0}")]
    NotFound(String),

    #[error("Query parse error: {0}")]
    QueryError(String),

    #[error("Schema error: {0}")]
    SchemaError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

impl From<tantivy::TantivyError> for DocumentError {
    fn from(e: tantivy::TantivyError) -> Self {
        DocumentError::IndexError(e.to_string())
    }
}

impl From<tantivy::query::QueryParserError> for DocumentError {
    fn from(e: tantivy::query::QueryParserError) -> Self {
        DocumentError::QueryError(e.to_string())
    }
}

impl From<tantivy::directory::error::OpenDirectoryError> for DocumentError {
    fn from(e: tantivy::directory::error::OpenDirectoryError) -> Self {
        DocumentError::IoError(std::io::Error::other(e.to_string()))
    }
}

/// A document for full-text indexing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    /// Unique identifier (matches Hexad entity ID)
    pub id: String,
    /// Document title
    pub title: String,
    /// Main content body
    pub body: String,
    /// Additional searchable fields
    pub fields: HashMap<String, String>,
    /// Non-searchable metadata
    pub metadata: HashMap<String, String>,
}

impl Document {
    /// Create a new document
    pub fn new(id: impl Into<String>, title: impl Into<String>, body: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            title: title.into(),
            body: body.into(),
            fields: HashMap::new(),
            metadata: HashMap::new(),
        }
    }

    /// Add a searchable field
    pub fn with_field(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.fields.insert(key.into(), value.into());
        self
    }

    /// Add metadata
    pub fn with_metadata(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.metadata.insert(key.into(), value.into());
        self
    }
}

/// Search result with score and highlights
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// Document ID
    pub id: String,
    /// Relevance score
    pub score: f32,
    /// Document title
    pub title: String,
    /// Snippet with highlights
    pub snippet: Option<String>,
}

/// Document store trait for cross-modal consistency
#[async_trait]
pub trait DocumentStore: Send + Sync {
    /// Index a document
    async fn index(&self, doc: &Document) -> Result<(), DocumentError>;

    /// Search documents
    async fn search(&self, query: &str, limit: usize) -> Result<Vec<SearchResult>, DocumentError>;

    /// Get document by ID
    async fn get(&self, id: &str) -> Result<Option<Document>, DocumentError>;

    /// Delete document by ID
    async fn delete(&self, id: &str) -> Result<(), DocumentError>;

    /// Commit pending changes
    async fn commit(&self) -> Result<(), DocumentError>;
}

/// Schema fields for Tantivy
struct DocumentSchema {
    id: Field,
    title: Field,
    body: Field,
    schema: Schema,
}

impl DocumentSchema {
    fn new() -> Self {
        let mut schema_builder = Schema::builder();
        let id = schema_builder.add_text_field("id", TEXT | STORED);
        let title = schema_builder.add_text_field("title", TEXT | STORED);
        let body = schema_builder.add_text_field("body", TEXT | STORED);
        let schema = schema_builder.build();

        Self { id, title, body, schema }
    }
}

/// Tantivy-backed document store
pub struct TantivyDocumentStore {
    schema: DocumentSchema,
    index: Index,
    writer: Arc<RwLock<IndexWriter>>,
    reader: IndexReader,
    documents: Arc<RwLock<HashMap<String, Document>>>,
}

impl TantivyDocumentStore {
    /// Create an in-memory store
    pub fn in_memory() -> Result<Self, DocumentError> {
        let schema = DocumentSchema::new();
        let index = Index::create_in_ram(schema.schema.clone());
        let writer = index.writer(50_000_000)?;
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()?;

        Ok(Self {
            schema,
            index,
            writer: Arc::new(RwLock::new(writer)),
            reader,
            documents: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    /// Create a persistent store
    pub fn persistent(path: impl AsRef<Path>) -> Result<Self, DocumentError> {
        let schema = DocumentSchema::new();
        std::fs::create_dir_all(path.as_ref())?;
        let dir = tantivy::directory::MmapDirectory::open(path)?;
        let index = Index::open_or_create(dir, schema.schema.clone())?;
        let writer = index.writer(50_000_000)?;
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()?;

        Ok(Self {
            schema,
            index,
            writer: Arc::new(RwLock::new(writer)),
            reader,
            documents: Arc::new(RwLock::new(HashMap::new())),
        })
    }
}

#[async_trait]
impl DocumentStore for TantivyDocumentStore {
    async fn index(&self, doc: &Document) -> Result<(), DocumentError> {
        let mut tantivy_doc = TantivyDocument::default();
        tantivy_doc.add_text(self.schema.id, &doc.id);
        tantivy_doc.add_text(self.schema.title, &doc.title);
        tantivy_doc.add_text(self.schema.body, &doc.body);

        // Delete existing document with same ID
        let term = tantivy::Term::from_field_text(self.schema.id, &doc.id);
        {
            let writer = self.writer.write().await;
            writer.delete_term(term);
            writer.add_document(tantivy_doc)?;
        }

        // Store original document
        self.documents.write().await.insert(doc.id.clone(), doc.clone());

        Ok(())
    }

    async fn search(&self, query: &str, limit: usize) -> Result<Vec<SearchResult>, DocumentError> {
        let searcher = self.reader.searcher();
        let query_parser = QueryParser::for_index(
            &self.index,
            vec![self.schema.title, self.schema.body],
        );

        let parsed_query = query_parser.parse_query(query)?;
        let top_docs = searcher.search(&parsed_query, &TopDocs::with_limit(limit))?;

        // Create snippet generator for body field
        let snippet_generator = SnippetGenerator::create(
            &searcher,
            &parsed_query,
            self.schema.body,
        )?;

        let mut results = Vec::new();
        for (score, doc_address) in top_docs {
            let retrieved_doc: TantivyDocument = searcher.doc(doc_address)?;

            let id = retrieved_doc
                .get_first(self.schema.id)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let title = retrieved_doc
                .get_first(self.schema.title)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            // Generate snippet with highlights
            let snippet = snippet_generator.snippet_from_doc(&retrieved_doc);
            let snippet_html = snippet.to_html();
            let snippet_text = if snippet_html.is_empty() {
                None
            } else {
                Some(snippet_html)
            };

            results.push(SearchResult {
                id,
                score,
                title,
                snippet: snippet_text,
            });
        }

        Ok(results)
    }

    async fn get(&self, id: &str) -> Result<Option<Document>, DocumentError> {
        Ok(self.documents.read().await.get(id).cloned())
    }

    async fn delete(&self, id: &str) -> Result<(), DocumentError> {
        let term = tantivy::Term::from_field_text(self.schema.id, id);
        self.writer.write().await.delete_term(term);
        self.documents.write().await.remove(id);
        Ok(())
    }

    async fn commit(&self) -> Result<(), DocumentError> {
        self.writer.write().await.commit()?;
        self.reader.reload()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_index_and_search() {
        let store = TantivyDocumentStore::in_memory().unwrap();

        let doc1 = Document::new("d1", "Rust Programming", "Rust is a systems programming language");
        let doc2 = Document::new("d2", "Python Tutorial", "Python is great for beginners");

        store.index(&doc1).await.unwrap();
        store.index(&doc2).await.unwrap();
        store.commit().await.unwrap();

        let results = store.search("Rust", 10).await.unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "d1");
    }

    #[tokio::test]
    async fn test_search_with_snippets() {
        let store = TantivyDocumentStore::in_memory().unwrap();

        let doc = Document::new(
            "d1",
            "Rust Guide",
            "Rust is a systems programming language focused on safety and performance",
        );
        store.index(&doc).await.unwrap();
        store.commit().await.unwrap();

        let results = store.search("safety", 10).await.unwrap();
        assert_eq!(results.len(), 1);
        assert!(results[0].snippet.is_some(), "Snippet should not be None");
        let snippet = results[0].snippet.as_ref().unwrap();
        assert!(snippet.contains("safety"), "Snippet should contain the search term");
    }
}
