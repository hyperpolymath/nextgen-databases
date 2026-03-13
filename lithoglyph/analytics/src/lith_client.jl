# SPDX-License-Identifier: PMPL-1.0-or-later
"""
HTTP client for Lith API
"""

"""
Lith HTTP client
"""
struct LithClient
    base_url::String
    timeout::Int

    function LithClient(base_url::String; timeout::Int=30)
        # Remove trailing slash
        url = rstrip(base_url, '/')
        new(url, timeout)
    end
end

"""
Document from Lith with provenance
"""
struct Document
    id::String
    data::Dict{String,Any}
    provenance::Union{Dict{String,Any},Nothing}
end

"""
    fetch_collection(client::LithClient, collection::String) -> Vector{Document}

Fetch all documents from a Lith collection.
"""
function fetch_collection(client::LithClient, collection::String)::Vector{Document}
    url = "$(client.base_url)/collections/$collection/documents"

    @info "Fetching documents from Lith" url

    response = HTTP.get(url; readtimeout=client.timeout)

    if response.status != 200
        error("Lith API error: $(response.status)")
    end

    docs_json = JSON3.read(String(response.body))

    documents = Document[]
    for doc in docs_json
        push!(documents, Document(
            string(doc.id),
            convert(Dict{String,Any}, doc.data),
            haskey(doc, :provenance) ? convert(Dict{String,Any}, doc.provenance) : nothing
        ))
    end

    @info "Fetched documents" count=length(documents) collection

    return documents
end

"""
    fetch_document(client::LithClient, collection::String, id::String) -> Document

Fetch a single document by ID.
"""
function fetch_document(client::LithClient, collection::String, id::String)::Document
    url = "$(client.base_url)/collections/$collection/documents/$id"

    response = HTTP.get(url; readtimeout=client.timeout)

    if response.status != 200
        error("Document not found: $id")
    end

    doc = JSON3.read(String(response.body))

    return Document(
        string(doc.id),
        convert(Dict{String,Any}, doc.data),
        haskey(doc, :provenance) ? convert(Dict{String,Any}, doc.provenance) : nothing
    )
end

"""
    health_check(client::LithClient) -> Bool

Check if Lith API is reachable.
"""
function health_check(client::LithClient)::Bool
    try
        url = "$(client.base_url)/health"
        response = HTTP.get(url; readtimeout=5)
        return response.status == 200
    catch
        return false
    end
end

"""
    extract_prompt_scores(doc::Document) -> Union{NamedTuple,Nothing}

Extract PROMPT scores from a document if present.
Returns (provenance, replicability, objective, methodology, publication, transparency).
"""
function extract_prompt_scores(doc::Document)
    data = doc.data

    # Try to find PROMPT scores in data
    prompt = get(data, "prompt_scores", get(data, "prompt", nothing))

    if isnothing(prompt)
        return nothing
    end

    if prompt isa Dict
        return (
            provenance = get(prompt, "provenance", get(prompt, "P", missing)),
            replicability = get(prompt, "replicability", get(prompt, "R", missing)),
            objective = get(prompt, "objective", get(prompt, "O", missing)),
            methodology = get(prompt, "methodology", get(prompt, "M", missing)),
            publication = get(prompt, "publication", get(prompt, "P2", missing)),
            transparency = get(prompt, "transparency", get(prompt, "T", missing))
        )
    end

    return nothing
end

"""
    extract_timestamp(doc::Document) -> Union{DateTime,Nothing}

Extract timestamp from document provenance or data.
"""
function extract_timestamp(doc::Document)
    # Try provenance first
    if !isnothing(doc.provenance)
        created_at = get(doc.provenance, "created_at", nothing)
        if !isnothing(created_at)
            try
                return DateTime(created_at[1:19], "yyyy-mm-ddTHH:MM:SS")
            catch
                # Try other formats
            end
        end
    end

    # Try data fields
    for field in ["created_at", "timestamp", "date", "created"]
        ts = get(doc.data, field, nothing)
        if !isnothing(ts) && ts isa String
            try
                return DateTime(ts[1:19], "yyyy-mm-ddTHH:MM:SS")
            catch
                continue
            end
        end
    end

    return nothing
end
