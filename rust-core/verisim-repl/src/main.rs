// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//!
//! VQL REPL — Interactive query shell for VeriSimDB.
//!
//! Provides a readline-based interactive shell with:
//! - VQL syntax highlighting
//! - Tab completion for keywords, modalities, and meta-commands
//! - Multiline query support (backslash continuation)
//! - Multiple output formats (table, JSON, CSV)
//! - Meta-commands for session control
//! - Query timing display
//! - Persistent command history

mod client;
mod completer;
mod formatter;
mod highlighter;
pub mod linter;
pub mod vql_fmt;

use clap::Parser;
use colored::Colorize;
use rustyline::config::Configurer;
use rustyline::error::ReadlineError;
use rustyline::hint::HistoryHinter;
use rustyline::history::DefaultHistory;
use rustyline::validate::MatchingBracketValidator;
use rustyline_derive::{Completer, Helper, Highlighter, Hinter, Validator};
use std::time::Instant;

use client::VqlClient;
use formatter::{format_value, OutputFormat};

/// VeriSimDB version string, pulled from Cargo.toml at compile time.
const VERSION: &str = env!("CARGO_PKG_VERSION");

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

/// VQL — Interactive query shell for VeriSimDB.
#[derive(Parser, Debug)]
#[command(name = "vql", version = VERSION, about = "VQL REPL for VeriSimDB")]
struct Cli {
    /// Hostname or IP of the verisim-api server.
    #[arg(long, default_value = "localhost")]
    host: String,

    /// Port of the verisim-api server.
    #[arg(long, default_value_t = 8080)]
    port: u16,

    /// Default output format.
    #[arg(long, default_value = "table")]
    format: String,
}

// ---------------------------------------------------------------------------
// Rustyline helper (bundles all traits into one type)
// ---------------------------------------------------------------------------

/// Combined helper that provides highlighting, completion, hinting, and
/// bracket validation for the rustyline editor.
#[derive(Helper, Highlighter, Completer, Hinter, Validator)]
struct VqlHelper {
    #[rustyline(Highlighter)]
    highlighter: highlighter::VqlHighlighter,
    #[rustyline(Completer)]
    completer: completer::VqlCompleter,
    #[rustyline(Hinter)]
    hinter: HistoryHinter,
    #[rustyline(Validator)]
    validator: MatchingBracketValidator,
}

// ---------------------------------------------------------------------------
// REPL session state
// ---------------------------------------------------------------------------

/// Mutable session state for the REPL loop.
struct Session {
    /// HTTP client for the verisim-api server.
    client: VqlClient,
    /// Current output format.
    format: OutputFormat,
    /// Whether to display query timing after each result.
    show_timing: bool,
}

impl Session {
    /// Create a new session from CLI arguments.
    fn new(host: &str, port: u16, format: OutputFormat) -> Self {
        let base_url = format!("http://{host}:{port}");
        let client = VqlClient::new(&base_url);
        Self {
            client,
            format,
            show_timing: false,
        }
    }

    /// Reconnect to a different host:port.
    fn reconnect(&mut self, addr: &str) {
        let base_url = if addr.starts_with("http://") || addr.starts_with("https://") {
            addr.to_string()
        } else {
            format!("http://{addr}")
        };
        self.client = VqlClient::new(&base_url);
        println!("Connected to {}", self.client.base_url());
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() {
    let cli = Cli::parse();

    let format: OutputFormat = cli.format.parse().unwrap_or_else(|e| {
        eprintln!("Warning: {e}. Defaulting to table format.");
        OutputFormat::Table
    });

    let mut session = Session::new(&cli.host, cli.port, format);

    // Print welcome banner.
    print_banner(&session);

    // Set up readline editor with helper.
    let helper = VqlHelper {
        highlighter: highlighter::VqlHighlighter,
        completer: completer::VqlCompleter,
        hinter: HistoryHinter::new(),
        validator: MatchingBracketValidator::new(),
    };

    let mut editor = rustyline::Editor::<VqlHelper, DefaultHistory>::new()
        .expect("failed to create readline editor");
    editor.set_helper(Some(helper));
    editor.set_auto_add_history(true);

    // Load history from ~/.vql_history (ignore errors on first run).
    let history_path = history_file_path();
    let _ = editor.load_history(&history_path);

    // Load .vqlrc from home directory if present.
    load_vqlrc(&mut session);

    // Main REPL loop.
    let mut query_buf = String::new();

    loop {
        let prompt = if query_buf.is_empty() {
            format!("{} ", "vql>".bright_green().bold())
        } else {
            format!("{} ", "  ..".bright_green())
        };

        match editor.readline(&prompt) {
            Ok(line) => {
                let trimmed = line.trim();

                // Empty line: if we have a buffer, treat it as end of input.
                if trimmed.is_empty() {
                    if !query_buf.is_empty() {
                        let query = std::mem::take(&mut query_buf);
                        execute_query(&mut session, query.trim());
                    }
                    continue;
                }

                // Multiline continuation: if the line ends with '\', append
                // the line (minus the backslash) and continue reading.
                if trimmed.ends_with('\\') {
                    let without_continuation = &trimmed[..trimmed.len() - 1];
                    if !query_buf.is_empty() {
                        query_buf.push(' ');
                    }
                    query_buf.push_str(without_continuation);
                    continue;
                }

                // If we have a pending buffer, append this line to it.
                if !query_buf.is_empty() {
                    query_buf.push(' ');
                    query_buf.push_str(trimmed);
                    let query = std::mem::take(&mut query_buf);
                    execute_query(&mut session, query.trim());
                    continue;
                }

                // Single-line input: check for meta-commands.
                if trimmed.starts_with('\\') {
                    if handle_meta_command(&mut session, trimmed) {
                        break; // \quit or \q
                    }
                    continue;
                }

                // Single-line VQL query.
                // Strip trailing semicolons (SQL habit).
                let query = trimmed.trim_end_matches(';');
                execute_query(&mut session, query);
            }
            Err(ReadlineError::Interrupted) => {
                // Ctrl-C: clear the current buffer.
                if !query_buf.is_empty() {
                    query_buf.clear();
                    println!("Query cancelled.");
                } else {
                    println!("Use \\quit or Ctrl-D to exit.");
                }
            }
            Err(ReadlineError::Eof) => {
                // Ctrl-D: exit.
                println!("Goodbye.");
                break;
            }
            Err(err) => {
                eprintln!("Readline error: {err}");
                break;
            }
        }
    }

    // Save history.
    let _ = editor.save_history(&history_path);
}

// ---------------------------------------------------------------------------
// Query execution
// ---------------------------------------------------------------------------

/// Send a VQL query to the server and display the result.
fn execute_query(session: &mut Session, query: &str) {
    if query.is_empty() {
        return;
    }

    let start = Instant::now();
    let result = session.client.execute(query);
    let elapsed = start.elapsed();

    match result {
        Ok(value) => {
            let output = format_value(&value, session.format);
            println!("{output}");
            if session.show_timing {
                println!(
                    "{}",
                    format!("Time: {:.3}ms", elapsed.as_secs_f64() * 1000.0).dimmed()
                );
            }
        }
        Err(e) => {
            eprintln!("{} {e}", "Error:".red().bold());
        }
    }
}

// ---------------------------------------------------------------------------
// Meta-command handling
// ---------------------------------------------------------------------------

/// Handle a meta-command (line starting with '\').
///
/// Returns `true` if the REPL should exit (on \quit or \q).
fn handle_meta_command(session: &mut Session, line: &str) -> bool {
    let parts: Vec<&str> = line.splitn(2, char::is_whitespace).collect();
    let cmd = parts[0];
    let arg = parts.get(1).map(|s| s.trim()).unwrap_or("");

    match cmd {
        "\\quit" | "\\q" => {
            println!("Goodbye.");
            return true;
        }
        "\\help" | "\\h" | "\\?" => {
            print_help();
        }
        "\\connect" => {
            if arg.is_empty() {
                println!(
                    "Current connection: {}",
                    session.client.base_url().bright_cyan()
                );
                println!("Usage: \\connect <host:port>");
            } else {
                session.reconnect(arg);
            }
        }
        "\\explain" => {
            if arg.is_empty() {
                println!("Usage: \\explain <VQL query>");
            } else {
                explain_query(session, arg);
            }
        }
        "\\timing" => {
            session.show_timing = !session.show_timing;
            println!(
                "Timing display: {}",
                if session.show_timing { "on" } else { "off" }
            );
        }
        "\\format" => {
            if arg.is_empty() {
                println!("Current format: {}", session.format);
                println!("Usage: \\format <table|json|csv>");
            } else {
                match arg.parse::<OutputFormat>() {
                    Ok(fmt) => {
                        session.format = fmt;
                        println!("Output format: {}", session.format);
                    }
                    Err(e) => {
                        eprintln!("{} {e}", "Error:".red().bold());
                    }
                }
            }
        }
        "\\status" => {
            check_status(session);
        }
        _ => {
            eprintln!(
                "{} Unknown command: {}. Type \\help for available commands.",
                "Error:".red().bold(),
                cmd
            );
        }
    }

    false
}

/// Send an EXPLAIN request and display the result.
fn explain_query(session: &Session, query: &str) {
    let start = Instant::now();
    let result = session.client.explain(query);
    let elapsed = start.elapsed();

    match result {
        Ok(value) => {
            // If the response has a text_output field, display that directly
            // for human-readable EXPLAIN. Otherwise use the standard formatter.
            if let Some(text) = value.get("text_output").and_then(|v| v.as_str()) {
                println!("{text}");
            } else {
                let output = format_value(&value, session.format);
                println!("{output}");
            }
            if session.show_timing {
                println!(
                    "{}",
                    format!("Time: {:.3}ms", elapsed.as_secs_f64() * 1000.0).dimmed()
                );
            }
        }
        Err(e) => {
            eprintln!("{} {e}", "Error:".red().bold());
        }
    }
}

/// Check server health and display the result.
fn check_status(session: &Session) {
    match session.client.health() {
        Ok(value) => {
            let output = format_value(&value, session.format);
            println!("{output}");
        }
        Err(e) => {
            eprintln!(
                "{} Server at {} is unreachable: {e}",
                "Error:".red().bold(),
                session.client.base_url()
            );
        }
    }
}

// ---------------------------------------------------------------------------
// .vqlrc loading
// ---------------------------------------------------------------------------

/// Load and execute commands from `~/.vqlrc` if the file exists.
///
/// Each non-empty, non-comment line in the file is treated as either a
/// meta-command or a VQL query (same as typing it at the prompt).
fn load_vqlrc(session: &mut Session) {
    let Some(home) = dirs::home_dir() else {
        return;
    };
    let rc_path = home.join(".vqlrc");
    if !rc_path.exists() {
        return;
    }

    let Ok(contents) = std::fs::read_to_string(&rc_path) else {
        return;
    };

    for line in contents.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if trimmed.starts_with('\\') {
            handle_meta_command(session, trimmed);
        } else {
            // Execute as VQL query (silently, during startup).
            let _ = session.client.execute(trimmed);
        }
    }
}

// ---------------------------------------------------------------------------
// History file path
// ---------------------------------------------------------------------------

/// Determine the history file path (~/.vql_history).
fn history_file_path() -> std::path::PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join(".vql_history")
}

// ---------------------------------------------------------------------------
// Help and banner
// ---------------------------------------------------------------------------

/// Print the welcome banner.
fn print_banner(session: &Session) {
    println!();
    println!(
        "{}",
        "  VeriSimDB VQL REPL".bright_cyan().bold()
    );
    println!(
        "  {} {}",
        "Version:".dimmed(),
        VERSION
    );
    println!(
        "  {} {}",
        "Server: ".dimmed(),
        session.client.base_url()
    );
    println!(
        "  {} {}",
        "Format: ".dimmed(),
        session.format
    );
    println!();
    println!(
        "  Type {} for help, {} to exit.",
        "\\help".bright_yellow(),
        "\\quit".bright_yellow()
    );
    println!();
}

/// Print the help text for meta-commands.
fn print_help() {
    println!();
    println!("{}", "  VQL Meta-Commands".bright_cyan().bold());
    println!();
    println!(
        "  {}  {}",
        "\\connect <host:port>".bright_yellow(),
        "Change server connection"
    );
    println!(
        "  {}  {}",
        "\\explain <query>    ".bright_yellow(),
        "Show EXPLAIN output for a query"
    );
    println!(
        "  {}  {}",
        "\\timing             ".bright_yellow(),
        "Toggle query timing display"
    );
    println!(
        "  {}  {}",
        "\\format <fmt>       ".bright_yellow(),
        "Set output format (table|json|csv)"
    );
    println!(
        "  {}  {}",
        "\\status             ".bright_yellow(),
        "Show server health status"
    );
    println!(
        "  {}  {}",
        "\\help               ".bright_yellow(),
        "Show this help message"
    );
    println!(
        "  {}  {}",
        "\\quit / \\q          ".bright_yellow(),
        "Exit the REPL"
    );
    println!();
    println!("{}", "  Query Input".bright_cyan().bold());
    println!();
    println!("  Enter VQL queries at the prompt. End with Enter to execute.");
    println!("  Use \\ at end of line for multiline continuation.");
    println!("  Trailing semicolons are stripped automatically.");
    println!();
}
