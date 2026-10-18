defmodule Mix.Tasks.Compile.HegelNif do
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    root = Path.expand("../..", File.cwd!())
    manifest = Path.join(root, "native/hegel_nif/Cargo.toml")
    output = Path.join(root, "native/hegel_nif/target/release/libhegel_nif.so")
    destination = Path.join(root, "priv/hegel_nif")

    unless File.exists?(manifest), do: Mix.raise("Hegel native manifest is missing: #{manifest}")

    {result, status} =
      System.cmd("cargo", ["build", "--release", "--manifest-path", manifest], stderr_to_stdout: true)

    if status != 0, do: Mix.raise("Hegel native engine failed to build:\n#{result}")
    unless File.exists?(output), do: Mix.raise("Hegel native engine did not produce #{output}")

    File.mkdir_p!(Path.dirname(destination))
    File.cp!(output, destination)
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
