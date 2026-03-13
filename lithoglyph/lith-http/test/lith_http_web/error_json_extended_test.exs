# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttpWeb.ErrorJSONExtendedTest do
  @moduledoc """
  Extended tests for ErrorJSON covering additional status codes.
  """

  use ExUnit.Case, async: true

  alias LithHttpWeb.ErrorJSON

  describe "render/2" do
    test "renders 400 Bad Request" do
      assert %{errors: %{detail: "Bad Request"}} = ErrorJSON.render("400.json", %{})
    end

    test "renders 401 Unauthorized" do
      assert %{errors: %{detail: "Unauthorized"}} = ErrorJSON.render("401.json", %{})
    end

    test "renders 403 Forbidden" do
      assert %{errors: %{detail: "Forbidden"}} = ErrorJSON.render("403.json", %{})
    end

    test "renders 404 Not Found" do
      assert %{errors: %{detail: "Not Found"}} = ErrorJSON.render("404.json", %{})
    end

    test "renders 429 Too Many Requests" do
      assert %{errors: %{detail: "Too Many Requests"}} = ErrorJSON.render("429.json", %{})
    end

    test "renders 500 Internal Server Error" do
      assert %{errors: %{detail: "Internal Server Error"}} = ErrorJSON.render("500.json", %{})
    end

    test "renders 501 Not Implemented" do
      assert %{errors: %{detail: "Not Implemented"}} = ErrorJSON.render("501.json", %{})
    end

    test "renders 503 Service Unavailable" do
      assert %{errors: %{detail: "Service Unavailable"}} = ErrorJSON.render("503.json", %{})
    end

    test "ignores assigns" do
      result = ErrorJSON.render("404.json", %{custom: "data"})
      assert result == %{errors: %{detail: "Not Found"}}
    end
  end
end
