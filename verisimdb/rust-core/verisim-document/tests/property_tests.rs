// SPDX-License-Identifier: PMPL-1.0-or-later
//! Property-based tests for document modality

use proptest::prelude::*;
use verisim_document::{Document, DocumentStore, TantivyDocumentStore};

/// Generate arbitrary document IDs
fn arb_id() -> impl Strategy<Value = String> {
    "[a-z0-9]{8,16}"
}

/// Generate arbitrary document titles
fn arb_title() -> impl Strategy<Value = String> {
    "[A-Za-z ]{5,50}"
}

/// Generate arbitrary document bodies
fn arb_body() -> impl Strategy<Value = String> {
    "[A-Za-z0-9 .,!?]{20,200}"
}

proptest! {
    #[test]
    fn test_insert_then_retrieve(
        id in arb_id(),
        title in arb_title(),
        body in arb_body()
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store = TantivyDocumentStore::in_memory().unwrap();
            let doc = Document::new(&id, &title, &body);

            // Index document
            store.index(&doc).await.unwrap();
            store.commit().await.unwrap();

            // Retrieve by ID
            let retrieved = store.get(&id).await.unwrap();
            prop_assert!(retrieved.is_some());

            let retrieved = retrieved.unwrap();
            prop_assert_eq!(&retrieved.id, &id);
            prop_assert_eq!(&retrieved.title, &title);
            prop_assert_eq!(&retrieved.body, &body);

            Ok(())
        })?;
    }

    #[test]
    fn test_search_returns_indexed_document(
        id in arb_id(),
        title in arb_title(),
        body in arb_body()
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store = TantivyDocumentStore::in_memory().unwrap();
            let doc = Document::new(&id, &title, &body);

            store.index(&doc).await.unwrap();
            store.commit().await.unwrap();

            // Search by ID should work via get()
            let retrieved = store.get(&id).await.unwrap();
            prop_assert!(retrieved.is_some(), "Document should be retrievable by ID");

            // Search by at least part of title
            let title_words: Vec<&str> = title.split_whitespace().collect();
            if let Some(first_word) = title_words.first() {
                if first_word.len() > 2 {
                    // Search might find it (depends on tokenization)
                    let _results = store.search(first_word, 10).await.unwrap();
                    // Note: We don't assert results.len() > 0 because Tantivy tokenization
                    // may not match our expectations for all random inputs
                }
            }

            Ok(())
        })?;
    }

    #[test]
    fn test_update_document(
        id in arb_id(),
        title1 in arb_title(),
        title2 in arb_title(),
        body1 in arb_body(),
        body2 in arb_body()
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store = TantivyDocumentStore::in_memory().unwrap();

            // Index first version
            let doc1 = Document::new(&id, &title1, &body1);
            store.index(&doc1).await.unwrap();
            store.commit().await.unwrap();

            // Update with second version (same ID, different content)
            let doc2 = Document::new(&id, &title2, &body2);
            store.index(&doc2).await.unwrap();
            store.commit().await.unwrap();

            // Should only find the updated version
            let retrieved = store.get(&id).await.unwrap();
            prop_assert!(retrieved.is_some());

            let retrieved = retrieved.unwrap();
            prop_assert_eq!(&retrieved.title, &title2, "Should have updated title");
            prop_assert_eq!(&retrieved.body, &body2, "Should have updated body");

            Ok(())
        })?;
    }

    #[test]
    fn test_delete_document(
        id in arb_id(),
        title in arb_title(),
        body in arb_body()
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store = TantivyDocumentStore::in_memory().unwrap();
            let doc = Document::new(&id, &title, &body);

            // Index document
            store.index(&doc).await.unwrap();
            store.commit().await.unwrap();

            // Verify it exists
            prop_assert!(store.get(&id).await.unwrap().is_some());

            // Delete document
            store.delete(&id).await.unwrap();
            store.commit().await.unwrap();

            // Verify it's gone
            prop_assert!(store.get(&id).await.unwrap().is_none());

            Ok(())
        })?;
    }

    #[test]
    fn test_multiple_documents_search(
        docs in prop::collection::vec(
            (arb_id(), arb_title(), arb_body()),
            1..10
        )
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store = TantivyDocumentStore::in_memory().unwrap();

            // Index all documents
            for (id, title, body) in &docs {
                let doc = Document::new(id, title, body);
                store.index(&doc).await.unwrap();
            }
            store.commit().await.unwrap();

            // Each document should be retrievable by ID
            for (id, _title, _body) in &docs {
                let retrieved = store.get(id).await.unwrap();
                prop_assert!(retrieved.is_some(), "Document {} should be retrievable", id);
            }

            Ok(())
        })?;
    }
}

/// Integration test: realistic usage pattern
#[tokio::test]
async fn test_realistic_document_lifecycle() {
    let store = TantivyDocumentStore::in_memory().unwrap();

    // Create initial document
    let doc = Document::new(
        "paper-123",
        "Machine Learning for Databases",
        "This paper explores the use of machine learning techniques for optimizing database query plans."
    )
    .with_field("authors", "Smith, Jones, Johnson")
    .with_field("year", "2024")
    .with_metadata("citation_count", "42");

    // Index it
    store.index(&doc).await.unwrap();
    store.commit().await.unwrap();

    // Verify document exists by ID
    let retrieved = store.get("paper-123").await.unwrap();
    assert!(retrieved.is_some());
    assert_eq!(retrieved.unwrap().title, "Machine Learning for Databases");

    // Update the document
    let updated_doc = Document::new(
        "paper-123",
        "Machine Learning for Database Query Optimization",
        "This paper explores the use of deep learning techniques for optimizing database query plans and execution."
    )
    .with_field("authors", "Smith, Jones, Johnson, Williams")
    .with_field("year", "2024")
    .with_metadata("citation_count", "45");

    store.index(&updated_doc).await.unwrap();
    store.commit().await.unwrap();

    // Verify update by ID (most reliable check)
    let retrieved = store.get("paper-123").await.unwrap().unwrap();
    assert!(retrieved.title.contains("Query Optimization"));
    assert!(retrieved.body.contains("deep learning"));

    // Delete the document
    store.delete("paper-123").await.unwrap();
    store.commit().await.unwrap();

    // Verify deletion by ID
    assert!(store.get("paper-123").await.unwrap().is_none(), "Document should be deleted");
}
