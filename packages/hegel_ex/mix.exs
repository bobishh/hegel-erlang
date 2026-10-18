defmodule Mix.Tasks.Compile.HegelNif do
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    package = Mix.Project.project_file() |> Path.dirname()
    root = Path.expand("../..", package)
    manifest = Path.join(root, "native/hegel_nif/Cargo.toml")
    output = Path.join(root, "native/hegel_nif/target/release/libhegel_nif.so")
    destination = Path.join(root, "priv/hegel_nif")
    build_destination =
      Mix.Project.build_path()
      |> Path.dirname()
      |> Path.join("hegel/priv/hegel_nif")
    lib_build_destination =
      Mix.Project.build_path()
      |> Path.join("lib/hegel/priv/hegel_nif")
    profile_destination =
      Mix.Project.build_path()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.join(Path.join(["_build", Atom.to_string(Mix.env()), "lib/hegel/priv/hegel_nif"]))

    unless File.exists?(manifest), do: Mix.raise("Hegel native manifest is missing: #{manifest}")

    {result, status} =
      System.cmd("cargo", ["build", "--release", "--manifest-path", manifest], stderr_to_stdout: true)

    if status != 0, do: Mix.raise("Hegel native engine failed to build:\n#{result}")
    unless File.exists?(output), do: Mix.raise("Hegel native engine did not produce #{output}")

    File.mkdir_p!(Path.dirname(destination))
    File.cp!(output, destination)
    File.mkdir_p!(Path.dirname(build_destination))
    File.cp!(output, build_destination)
    File.mkdir_p!(Path.dirname(lib_build_destination))
    File.cp!(output, lib_build_destination)
    File.mkdir_p!(Path.dirname(profile_destination))
    File.cp!(output, profile_destination)
    :ok
  end
end

defmodule HegelEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :hegel_ex,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:hegel_nif] ++ Mix.compilers(),
      description: "Idiomatic Elixir facade for the Erlang Hegel SDK",
      package: [
        licenses: ["MIT"],
        links: %{
          "Hegel" => "https://hegel.dev",
          "GitHub" => "https://github.com/ghuntley/hegel-erlang"
        }
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
  defp deps, do: [{:hegel, path: "../.."}]
end
