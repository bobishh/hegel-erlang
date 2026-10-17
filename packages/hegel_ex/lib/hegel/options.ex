defmodule Hegel.Options do
  @type t :: map()
  @spec validate(keyword() | map()) :: t()
  def validate(options) when is_list(options), do: options |> Map.new() |> validate()
  def validate(options) when is_map(options) do
    unless is_integer(Map.get(options, :test_cases, 100)) and Map.get(options, :test_cases, 100) > 0 do
      raise ArgumentError, "test_cases must be a positive integer"
    end
    options
  end
end
