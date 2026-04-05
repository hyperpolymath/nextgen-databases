defmodule QuandleDBNif.MixProject do
  use Mix.Project

  def project do
    [
      app: :quandle_db_nif,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      "nif.build": [&build_nif/1],
      "nif.clean": [&clean_nif/1],
      compile: ["nif.build", "compile"],
      test: [&set_stub_mode_for_tests/1, "nif.build", "test"]
    ]
  end

  defp set_stub_mode_for_tests(_args) do
    live_base = System.get_env("QDB_LIVE_TEST_BASE_URL")

    if is_binary(live_base) and live_base != "" do
      System.put_env("QDB_NIF_MODE", "live")
      System.put_env("QDB_API_BASE_URL", live_base)
    else
      System.put_env("QDB_NIF_MODE", "stub")
    end

    :ok
  end

  defp build_nif(_args) do
    project_root = File.cwd!()
    source = Path.join(project_root, "native/quandle_db_nif.zig")
    priv_dir = Path.join(project_root, "priv")

    File.mkdir_p!(priv_dir)

    output = Path.join(priv_dir, "quandle_db_nif#{shared_lib_ext()}")
    include_dir = erlang_include_dir()

    args = [
      "build-lib",
      source,
      "-dynamic",
      "-fPIC",
      "-O",
      "ReleaseSafe",
      "-lc",
      "-I",
      include_dir,
      "-femit-bin=#{output}"
    ]

    case System.cmd("zig", args, stderr_to_stdout: true, cd: project_root) do
      {_, 0} ->
        Mix.shell().info("Built NIF: #{output}")
        :ok

      {output_text, _} ->
        Mix.raise("Failed to build NIF:\n#{output_text}")
    end
  end

  defp clean_nif(_args) do
    project_root = File.cwd!()
    File.rm(Path.join(project_root, "priv/quandle_db_nif#{shared_lib_ext()}"))
    :ok
  end

  defp erlang_include_dir do
    root = :code.root_dir() |> List.to_string()
    version = :erlang.system_info(:version) |> List.to_string()
    Path.join([root, "erts-#{version}", "include"])
  end

  defp shared_lib_ext do
    case :os.type() do
      {:unix, :darwin} -> ".dylib"
      {:win32, _} -> ".dll"
      _ -> ".so"
    end
  end
end
