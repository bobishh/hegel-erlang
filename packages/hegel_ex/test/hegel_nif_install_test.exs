defmodule HegelNifInstallTest do
  use ExUnit.Case, async: true
  alias Mix.Tasks.Compile.HegelNif

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "hegel-install-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "replacement preserves the old inode and executable permissions", %{directory: directory} do
    source = Path.join(directory, "source.so")
    destination = Path.join(directory, "installed.so")
    File.write!(source, "new native image")
    File.chmod!(source, 0o755)
    File.write!(destination, "old mapped image")
    previous = File.stat!(destination)
    descriptor = File.open!(destination, [:read, :binary])

    try do
      assert :ok = HegelNif.install_native!(source, destination)
      assert File.stat!(destination).inode != previous.inode
      assert IO.binread(descriptor, :eof) == "old mapped image"
      assert File.read!(destination) == "new native image"
      assert Bitwise.band(File.stat!(destination).mode, 0o777) == 0o755
      assert Path.wildcard(destination <> ".install-*") == []
    after
      File.close(descriptor)
    end
  end

  test "concurrent installers publish complete files and remove staging", %{directory: directory} do
    destination = Path.join(directory, "installed.so")
    images = for n <- 1..8, do: :binary.copy(<<n>>, 100_000)

    images
    |> Enum.with_index()
    |> Enum.map(fn {image, index} ->
      source = Path.join(directory, "source-#{index}.so")
      File.write!(source, image)
      Task.async(fn -> HegelNif.install_native!(source, destination) end)
    end)
    |> Enum.each(fn task -> assert Task.await(task) == :ok end)

    assert File.read!(destination) in images
    assert Path.wildcard(destination <> ".install-*") == []
  end

  test "failed copy preserves the installed library and removes staging", %{directory: directory} do
    destination = Path.join(directory, "installed.so")
    File.write!(destination, "working library")
    previous = File.stat!(destination)

    assert_raise File.CopyError, fn ->
      HegelNif.install_native!(Path.join(directory, "missing.so"), destination)
    end

    assert File.read!(destination) == "working library"
    assert File.stat!(destination).inode == previous.inode
    assert Path.wildcard(destination <> ".install-*") == []
  end
end
