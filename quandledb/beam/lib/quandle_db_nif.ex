defmodule QuandleDBNif do
  @moduledoc """
  Thin Elixir wrapper over the Zig NIF boundary.

  The NIF implementation is intentionally minimal and currently returns
  scaffolded semantic payload shapes for:

  * `semantic_lookup/1`
  * `semantic_equivalents/1`
  """

  alias QuandleDBNif.Native

  @spec semantic_lookup(binary()) :: {:ok, map()} | {:error, atom()}
  def semantic_lookup(name) when is_binary(name) do
    Native.semantic_lookup(name)
  end

  def semantic_lookup(_), do: {:error, :invalid_argument}

  @spec semantic_equivalents(binary()) :: {:ok, map()} | {:error, atom()}
  def semantic_equivalents(name) when is_binary(name) do
    Native.semantic_equivalents(name)
  end

  def semantic_equivalents(_), do: {:error, :invalid_argument}
end
