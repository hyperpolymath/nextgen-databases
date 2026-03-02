# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VeriSimDB Julia Client — Test suite.
#
# Basic unit tests for the VeriSimDBClient package. These tests validate
# type construction, error handling, and client configuration without
# requiring a running VeriSimDB server.

using Test
using VeriSimDBClient

@testset "VeriSimDBClient" begin

    @testset "Client construction" begin
        # Unauthenticated client
        c = Client("http://localhost:8080")
        @test c.base_url == "http://localhost:8080"
        @test c.timeout == 30
        @test c.auth isa NoAuth

        # Client with API key
        c_api = Client("http://localhost:8080", ApiKeyAuth("test-key"))
        @test c_api.auth isa ApiKeyAuth

        # Client with Bearer token
        c_bearer = Client("http://localhost:8080", BearerAuth("my-token"))
        @test c_bearer.auth isa BearerAuth

        # Client with Basic auth
        c_basic = Client("http://localhost:8080", BasicAuth("user", "pass"))
        @test c_basic.auth isa BasicAuth

        # Trailing slash is stripped
        c_slash = Client("http://localhost:8080/")
        @test c_slash.base_url == "http://localhost:8080"

        # Keyword constructor
        c_kw = Client("http://localhost:8080"; timeout=60)
        @test c_kw.timeout == 60
    end

    @testset "Type construction" begin
        # ModalityStatus defaults
        ms = ModalityStatus()
        @test ms.graph == false
        @test ms.vector == false

        # HexadInput keyword constructor
        hi = HexadInput(modalities=[Graph, Vector])
        @test length(hi.modalities) == 2
        @test hi.graph_data === nothing
        @test hi.metadata == Dict{String,String}()

        # ProvenanceEventInput
        pei = ProvenanceEventInput("annotation", "test-user", Dict("key" => "value"))
        @test pei.event_type == "annotation"
        @test pei.actor == "test-user"

        # PeerRegistration
        pr = PeerRegistration("peer-1", "http://peer1:8080")
        @test pr.name == "peer-1"
        @test pr.metadata == Dict{String,String}()

        # FederatedQueryRequest keyword constructor
        fqr = FederatedQueryRequest("FIND hexads"; timeout=5000)
        @test fqr.query == "FIND hexads"
        @test fqr.timeout == 5000
        @test fqr.peer_ids == String[]
    end

    @testset "Error types" begin
        # Error construction
        e_bad = BadRequestError("invalid input")
        @test e_bad.message == "invalid input"
        @test e_bad isa VeriSimError

        e_notfound = NotFoundError("not found")
        @test e_notfound isa VeriSimError

        # Retryable errors
        @test is_retryable(RateLimitedError("slow down")) == true
        @test is_retryable(InternalServerError("oops")) == true
        @test is_retryable(ServiceUnavailableError("busy")) == true
        @test is_retryable(ConnectionError("disconnected")) == true
        @test is_retryable(TimeoutError("too slow", 30000)) == true

        # Non-retryable errors
        @test is_retryable(BadRequestError("bad")) == false
        @test is_retryable(UnauthorizedError("no auth")) == false
        @test is_retryable(NotFoundError("missing")) == false
        @test is_retryable(ConflictError("conflict")) == false

        # error_from_status
        @test error_from_status(400, "bad") isa BadRequestError
        @test error_from_status(401, "unauth") isa UnauthorizedError
        @test error_from_status(403, "forbidden") isa ForbiddenError
        @test error_from_status(404, "missing") isa NotFoundError
        @test error_from_status(409, "conflict") isa ConflictError
        @test error_from_status(422, "invalid") isa ValidationError
        @test error_from_status(429, "limit") isa RateLimitedError
        @test error_from_status(500, "error") isa InternalServerError
        @test error_from_status(503, "unavailable") isa ServiceUnavailableError
        @test error_from_status(999, "unknown") isa InternalServerError
    end

    @testset "Modality enum" begin
        @test Graph isa Modality
        @test Vector isa Modality
        @test Tensor isa Modality
        @test Semantic isa Modality
        @test Document isa Modality
        @test Temporal isa Modality
        @test Provenance isa Modality
        @test Spatial isa Modality
    end

    @testset "DriftLevel enum" begin
        @test DriftStable isa DriftLevel
        @test DriftLow isa DriftLevel
        @test DriftModerate isa DriftLevel
        @test DriftHigh isa DriftLevel
        @test DriftCritical isa DriftLevel
    end

end # @testset "VeriSimDBClient"
