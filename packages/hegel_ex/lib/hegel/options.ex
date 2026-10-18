defmodule Hegel.Options do
  @typedoc """
  Where a property lives: source file, line, enclosing module and test
  function. The engine reports each run with a location to Antithesis as the
  assertion `Module::function passes properties`.
  """
  @type location :: {String.t(), non_neg_integer(), String.t(), String.t()}
  @type t :: map()
  @spec validate(keyword() | map()) :: t()
  def validate(options) when is_list(options), do: options |> Map.new() |> validate()

  def validate(options) when is_map(options) do
    supported = [
      :profile,
      :test_cases,
      :seed,
      :derandomize,
      :database,
      :report_multiple_failures,
      :show_statistics,
      :print_blob,
      :location
    ]

    unknown = Map.keys(options) -- supported

    if unknown != [] do
      raise ArgumentError,
            "unsupported Hegel options: #{inspect(Enum.sort(unknown))}; " <>
              "use test_cases on the outer runner to set the exploration budget"
    end

    unless is_integer(Map.get(options, :test_cases, 100)) and
             Map.get(options, :test_cases, 100) > 0 do
      raise ArgumentError, "test_cases must be a positive integer"
    end

    validate_location(Map.get(options, :location))
    if Map.get(options, :location) == nil, do: Map.delete(options, :location), else: options
  end

  defp validate_location(nil), do: :ok

  defp validate_location({file, line, module, function})
       when is_binary(file) and file != "" and is_integer(line) and line >= 0 and
              line <= 0xFFFFFFFF and is_binary(module) and module != "" and
              is_binary(function) and function != "",
       do: :ok

  defp validate_location(other) do
    raise ArgumentError,
          "location must be {file, line, module, function} with non-empty strings, got: " <>
            inspect(other)
  end
end
