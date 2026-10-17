defmodule Hegel.TestCase do
  @moduledoc "Opaque handle for a generated case."
  @type t :: term()
  @spec current() :: t()
  def current, do: :hegel.current_test_case()
end
