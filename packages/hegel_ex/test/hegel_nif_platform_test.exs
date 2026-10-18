defmodule HegelNifPlatformTest do
  use ExUnit.Case, async: true

  test "Darwin builds use Cargo's dylib filename" do
    assert Mix.Tasks.Compile.HegelNif.native_library_filename({:unix, :darwin}) ==
             "libhegel_nif.dylib"
  end

  test "Linux builds retain Cargo's shared object filename" do
    assert Mix.Tasks.Compile.HegelNif.native_library_filename({:unix, :linux}) ==
             "libhegel_nif.so"
  end
end
