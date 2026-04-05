defmodule QuandleDBNif.Native do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    app = :quandle_db_nif
    filename = ~c"quandle_db_nif"
    path = :filename.join(:code.priv_dir(app), filename)
    :erlang.load_nif(path, 0)
  end

  def semantic_lookup(_name), do: :erlang.nif_error(:nif_not_loaded)
  def semantic_equivalents(_name), do: :erlang.nif_error(:nif_not_loaded)
end
