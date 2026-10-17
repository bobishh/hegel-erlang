defmodule Hegel.Task do
  @moduledoc "Concurrent work with a cloned Hegel test case."
  @spec async((-> term())) :: {pid(), reference()}
  def async(fun) when is_function(fun, 0), do: async(:hegel.current_test_case(), fun)
  @spec async(Hegel.TestCase.t(), (-> term())) :: {pid(), reference()}
  def async(test_case, fun) when is_function(fun, 0), do: :hegel_process.spawn(test_case, fn _ -> fun.() end)
  defdelegate await(task), to: :hegel_process
end
