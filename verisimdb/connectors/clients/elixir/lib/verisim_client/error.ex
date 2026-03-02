# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Error do
  @moduledoc """
  Error types for the VeriSimDB Elixir client SDK.

  Errors are represented as exception structs so they can be raised with
  `raise/1` or matched in `{:error, reason}` tuples. Each error type carries
  enough context for callers to decide whether to retry, surface a user-facing
  message, or escalate.
  """

  # ---------------------------------------------------------------------------
  # NotFound
  # ---------------------------------------------------------------------------

  defmodule NotFound do
    @moduledoc "The requested entity (hexad, peer, provenance record) was not found."
    defexception [:message]

    @impl true
    def exception(id) do
      %__MODULE__{message: "Entity not found: #{id}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Unauthorized
  # ---------------------------------------------------------------------------

  defmodule Unauthorized do
    @moduledoc "Authentication or authorization failed."
    defexception [:message]

    @impl true
    def exception(reason) do
      %__MODULE__{message: "Unauthorized: #{reason}"}
    end
  end

  # ---------------------------------------------------------------------------
  # NetworkError
  # ---------------------------------------------------------------------------

  defmodule NetworkError do
    @moduledoc "An underlying HTTP / network transport error."
    defexception [:message, :reason]

    @impl true
    def exception(reason) do
      %__MODULE__{message: "Network error: #{inspect(reason)}", reason: reason}
    end
  end

  # ---------------------------------------------------------------------------
  # ServerError
  # ---------------------------------------------------------------------------

  defmodule ServerError do
    @moduledoc "The server returned an HTTP error status."
    defexception [:message, :status]

    @impl true
    def exception({status, message}) do
      %__MODULE__{
        message: "Server error (#{status}): #{message}",
        status: status
      }
    end
  end

  # ---------------------------------------------------------------------------
  # ValidationError
  # ---------------------------------------------------------------------------

  defmodule ValidationError do
    @moduledoc "Client-side validation failed before the request was sent."
    defexception [:message]

    @impl true
    def exception(reason) do
      %__MODULE__{message: "Validation error: #{reason}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Timeout
  # ---------------------------------------------------------------------------

  defmodule Timeout do
    @moduledoc "The request exceeded the configured timeout duration."
    defexception [:message, :timeout_ms]

    @impl true
    def exception(timeout_ms) do
      %__MODULE__{
        message: "Timeout after #{timeout_ms}ms",
        timeout_ms: timeout_ms
      }
    end
  end
end
