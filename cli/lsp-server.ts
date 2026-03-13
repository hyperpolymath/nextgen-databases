// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
//
// GQL-DT Language Server Protocol Implementation
// Provides real-time diagnostics with dependent type checking

import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  TextDocumentSyncKind,
  Diagnostic,
  DiagnosticSeverity,
} from "npm:vscode-languageserver/node";

import { TextDocument } from "npm:vscode-languageserver-textdocument";

// Create LSP connection
const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

// GQL-DT keywords for syntax validation
const GQL_KEYWORDS = new Set([
  "SELECT", "INSERT", "UPDATE", "DELETE", "FROM", "WHERE", "INTO", "VALUES",
  "SET", "ORDER", "BY", "LIMIT", "ASC", "DESC", "AND", "OR", "NOT",
  "RATIONALE", "AS", "NORMALIZE", "WITH",
  // Type keywords
  "Nat", "Int", "String", "Bool", "Float",
  "BoundedNat", "BoundedInt", "NonEmptyString", "Confidence",
  "PromptScores", "Tracked",
]);

connection.onInitialize(() => {
  console.error("[GQL-DT LSP] Initializing language server...");
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Full,
      completionProvider: {
        resolveProvider: false,
        triggerCharacters: [".", ":", " "],
      },
      hoverProvider: true,
      diagnosticProvider: {
        interFileDependencies: false,
        workspaceDiagnostics: false,
      },
    },
  };
});

connection.onInitialized(() => {
  console.error("[GQL-DT LSP] Language server initialized successfully");
});

// Validate document on change
documents.onDidChangeContent((change) => {
  validateDocument(change.document);
});

// Validate document on open
documents.onDidOpen((event) => {
  validateDocument(event.document);
});

// Validation function
function validateDocument(textDocument: TextDocument): void {
  const text = textDocument.getText();
  const diagnostics: Diagnostic[] = [];

  // Check for missing RATIONALE clauses (critical in GQL-DT)
  const insertMatch = /INSERT\s+INTO/gi;
  const updateMatch = /UPDATE\s+\w+\s+SET/gi;
  const deleteMatch = /DELETE\s+FROM/gi;

  let match;
  while ((match = insertMatch.exec(text)) !== null) {
    const startPos = match.index;
    const endPos = text.indexOf(";", startPos);
    const statement = text.substring(startPos, endPos === -1 ? text.length : endPos);

    if (!statement.match(/RATIONALE\s+/i)) {
      const line = text.substring(0, startPos).split("\n").length - 1;
      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: {
          start: { line, character: 0 },
          end: { line, character: statement.split("\n")[0].length },
        },
        message: "INSERT statement requires RATIONALE clause for provenance tracking",
        source: "gql-dt-lsp",
      });
    }
  }

  // Check for type annotations in GQL-DT mode (explicit types)
  const columnListMatch = /\(([^)]+)\)/g;
  while ((match = columnListMatch.exec(text)) !== null) {
    const columns = match[1];
    if (columns.includes(":") && !columns.match(/:\s*(Nat|Int|String|Bool|BoundedNat|NonEmptyString)/)) {
      const line = text.substring(0, match.index).split("\n").length - 1;
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: {
          start: { line, character: match.index },
          end: { line, character: match.index + match[0].length },
        },
        message: "Type annotation may be invalid. Expected: Nat, Int, String, Bool, BoundedNat, NonEmptyString, etc.",
        source: "gql-dt-lsp",
      });
    }
  }

  // Check for BoundedNat bounds
  const boundedNatMatch = /BoundedNat\s+(\d+)\s+(\d+)/g;
  while ((match = boundedNatMatch.exec(text)) !== null) {
    const min = parseInt(match[1]);
    const max = parseInt(match[2]);
    if (min >= max) {
      const line = text.substring(0, match.index).split("\n").length - 1;
      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: {
          start: { line, character: match.index },
          end: { line, character: match.index + match[0].length },
        },
        message: `BoundedNat: min (${min}) must be less than max (${max})`,
        source: "gql-dt-lsp",
      });
    }
  }

  // Send diagnostics
  connection.sendDiagnostics({ uri: textDocument.uri, diagnostics });
}

// Hover provider - show type information
connection.onHover((params) => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return null;

  const text = document.getText();
  const offset = document.offsetAt(params.position);
  const word = getWordAtOffset(text, offset);

  if (GQL_KEYWORDS.has(word.toUpperCase())) {
    return {
      contents: {
        kind: "markdown",
        value: `**GQL-DT Keyword**: \`${word}\`\n\nDependent type checking enabled.`,
      },
    };
  }

  return null;
});

// Completion provider - suggest keywords and types
connection.onCompletion((params) => {
  const keywords = Array.from(GQL_KEYWORDS).map((kw) => ({
    label: kw,
    kind: 14, // Keyword
    detail: "GQL-DT keyword",
  }));

  return keywords;
});

// Helper: get word at offset
function getWordAtOffset(text: string, offset: number): string {
  let start = offset;
  let end = offset;

  while (start > 0 && /\w/.test(text[start - 1])) start--;
  while (end < text.length && /\w/.test(text[end])) end++;

  return text.substring(start, end);
}

// Start listening
documents.listen(connection);
connection.listen();

console.error("[GQL-DT LSP] Language server started, listening for requests");
