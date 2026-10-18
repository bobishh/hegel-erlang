defmodule HegelAntithesisTest do
  use ExUnit.Case, async: true
  require Hegel

  # ERTS keeps its own copy of the environment, so System.put_env/2 never
  # reaches the engine's getenv; each case runs a child VM started with
  # ANTITHESIS_OUTPUT_DIR set, as Antithesis starts its processes.
  @moduletag timeout: 180_000

  @probe """
  defmodule HegelProbe do
    use Hegel

    def passing do
      check all(x <- integer(0, 10), test_cases: 5) do
        true = x in 0..10
      end
    end

    def explicit do
      Hegel.check(fn -> :ok end, test_cases: 1, location: {"a.exs", 3, "Custom", "named"})
    end
  end
  """

  test "check names the enclosing module and function" do
    assert [declared, evaluated] = child("HegelProbe.passing()")
    assert %{"hit" => false, "must_hit" => true, "assert_type" => "always"} = declared
    assert %{"hit" => true, "condition" => true} = evaluated
    assert declared["id"] == "HegelProbe::passing passes properties"

    assert %{"class" => "HegelProbe", "function" => "passing", "file" => file} =
             declared["location"]

    assert Path.basename(file) == "probe.exs"
  end

  test "an explicit location is kept" do
    assert [%{"id" => "Custom::named passes properties"}, _evaluated] =
             child("HegelProbe.explicit()")
  end

  test "an invalid location is refused" do
    assert_raise ArgumentError, ~r/location/, fn ->
      Hegel.check(fn -> :ok end, test_cases: 1, location: {"", 1, "M", "f"})
    end
  end

  defp child(call) do
    dir = Path.join(System.tmp_dir!(), "hegel-ex-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      script = Path.join(dir, "probe.exs")
      File.write!(script, @probe <> "\n" <> call <> "\n")
      paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

      {output, status} =
        System.cmd(System.find_executable("elixir"), paths ++ [script],
          env: [{"ANTITHESIS_OUTPUT_DIR", dir}],
          stderr_to_stdout: true
        )

      assert status == 0, output

      case File.read(Path.join(dir, "sdk.jsonl")) do
        {:ok, text} ->
          text
          |> String.split("\n", trim: true)
          |> Enum.map(&(JSON.decode!(&1) |> Map.fetch!("antithesis_assert")))

        {:error, :enoent} ->
          []
      end
    after
      File.rm_rf!(dir)
    end
  end
end
