# SPDX-License-Identifier: PMPL-1.0-or-later
#
# src/vcl_server.jl — Julia stdio server for the verisim CLI.
#
# Protocol (per src/Abi/VCLProtocol.idr):
#   stdin  : one VCL query per line, terminated by newline
#   stdout : one A2ML [vcl-verdict] block per query, followed by a blank line
#
# The server runs until stdin is closed (EOF). Errors in parse_vcl or prove
# are caught and returned as result = "ParseError" / "RuntimeError" so that
# the calling process (the Zig CLI) is never left waiting for a verdict.
#
# Invoked by the Zig CLI as:
#   julia --project=<package_path> <package_path>/src/vcl_server.jl
#
# The `--project` flag ensures that `using Verisim` resolves the local
# package. The server shares a single Store and Manager across all queries
# in a session, so state is accumulated within a process lifetime.

using Verisim

# ---------------------------------------------------------------------------
# Initialise shared state
# ---------------------------------------------------------------------------

const _store   = Verisim.Store()
const _manager = Verisim.Manager()

# ---------------------------------------------------------------------------
# A2ML verdict serialiser
# ---------------------------------------------------------------------------

"""
    emit_verdict(query::AbstractString, result::AbstractString, error=nothing)

Write one A2ML [vcl-verdict] block to stdout, followed by a blank line to
delimit consecutive verdicts. The blank line is the record separator the Zig
reader uses to detect a complete verdict.
"""
function emit_verdict(query::AbstractString, result::AbstractString,
                      error::Union{AbstractString,Nothing}=nothing)
    println("[vcl-verdict]")
    # Escape embedded double-quotes and newlines in query text.
    safe_query = replace(replace(query, '\\' => "\\\\"), '"' => "\\\"")
    println("query = \"$(safe_query)\"")
    println("result = \"$(result)\"")
    if error !== nothing
        safe_err = replace(replace(error, '\\' => "\\\\"), '"' => "\\\"")
        println("error = \"$(safe_err)\"")
    end
    println()      # blank line = record separator
    flush(stdout)  # critical: the Zig reader blocks on read(); flush every verdict
end

# ---------------------------------------------------------------------------
# Main server loop
# ---------------------------------------------------------------------------

for line in eachline(stdin)
    query_text = strip(line)

    # Skip blank lines (e.g. the blank separator the client might echo back).
    isempty(query_text) && continue

    # Parse phase.
    q = try
        Verisim.parse_vcl(query_text)
    catch e
        emit_verdict(query_text, "ParseError", sprint(showerror, e))
        continue
    end

    # Prove phase.
    verdict = try
        Verisim.prove(q, _store, _manager)
    catch e
        emit_verdict(query_text, "RuntimeError", sprint(showerror, e))
        continue
    end

    # Classify verdict by type name — VerdictPass / VerdictFail.
    result_str = if verdict isa Main.VCLQuery.VerdictPass
        "Pass"
    elseif verdict isa Main.VCLQuery.VerdictFail
        "Fail"
    else
        "RuntimeError"
    end

    emit_verdict(query_text, result_str)
end
