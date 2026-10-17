defmodule Hegel.Gen do
  @moduledoc "Composable generators. Values are shrunk by Hegel's native engine."
  @type t :: term()
  defdelegate boolean(), to: :hegel_gen
  defdelegate boolean(probability), to: :hegel_gen
  defdelegate integer(), to: :hegel_gen
  defdelegate integer(min, max), to: :hegel_gen
  def integer(%Range{first: first, last: last}), do: integer(first, last)
  defdelegate float(), to: :hegel_gen
  defdelegate float(min, max), to: :hegel_gen
  defdelegate binary(), to: :hegel_gen
  defdelegate binary(min, max), to: :hegel_gen
  def binary(options) when is_list(options) do
    case Keyword.get(options, :length) do
      nil -> binary(Keyword.get(options, :min_length, 0), Keyword.get(options, :max_length, 256))
      length -> binary(length, length)
    end
  end
  @spec term() :: term()
  def term do
    one_of([integer(), boolean(), binary(), utf8()])
  end

  defdelegate utf8(), to: :hegel_gen
  defdelegate utf8(min, max), to: :hegel_gen
  defdelegate constant(value), to: :hegel_gen
  defdelegate one_of(generators), to: :hegel_gen
  defdelegate frequency(weighted), to: :hegel_gen
  defdelegate tuple(generators), to: :hegel_gen
  defdelegate map(fields), to: :hegel_gen
  @spec member_of([term()]) :: term()
  def member_of(values) when is_list(values), do: one_of(Enum.map(values, &constant/1))
  @spec list_of(term(), keyword()) :: term()
  def list_of(generator, options \\ []), do: list(generator, options)
  @spec uniq_list_of(term(), keyword()) :: term()
  def uniq_list_of(generator, options \\ []) do
    min = Keyword.get(options, :min, 0)
    max = Keyword.get(options, :max, 16)
    map(list(generator, min: min, max: max), &Enum.uniq/1)
  end

  @spec optional(term(), keyword()) :: term()
  def optional(generator, options \\ []) do
    probability = Keyword.get(options, :probability, 0.5)
    frequency([{probability, constant(nil)}, {1.0 - probability, generator}])
  end

  @spec string(keyword()) :: term()
  def string(options \\ []),
    do:
      map(
        binary(
          Keyword.get(options, :length, Keyword.get(options, :min_length, Keyword.get(options, :min, 0))),
          Keyword.get(options, :length, Keyword.get(options, :max_length, Keyword.get(options, :max, 64)))
        ),
        fn value ->
          value
          |> String.replace_invalid()
          |> then(fn text ->
            if Keyword.get(options, :kind) in [:alphanumeric, :ascii] do
              String.replace(text, ~r/[^A-Za-z0-9]/, "a")
            else
              text
            end
          end)
        end
      )

  def string(kind, options), do: string(Keyword.put(options, :kind, kind))

  @spec map_of(term(), term(), keyword()) :: term()
  def map_of(key, value, options \\ []) do
    map(list_of(tuple([key, value]), options), &Map.new/1)
  end

  def map(generator, fun), do: :hegel_gen.map(fun, generator)
  def bind(generator, fun), do: :hegel_gen.bind(generator, fun)
  def filter(generator, fun), do: :hegel_gen.filter(fun, generator)
  def list(generator), do: :hegel_gen.list(generator)
  def list(generator) when is_tuple(generator), do: :hegel_gen.list(tuple(Tuple.to_list(generator)))

  def list(generator, options) do
    generator = if is_tuple(generator), do: tuple(Tuple.to_list(generator)), else: generator
    :hegel_gen.list(generator, Keyword.get(options, :min, Keyword.get(options, :min_length, 0)), Keyword.get(options, :max, Keyword.get(options, :max_length, 16)))
  end

  def resize(generator, max) when is_integer(max) and max >= 0,
    do: list(generator, min: 0, max: max)

  def shuffle(values) when is_list(values), do: constant(Enum.shuffle(values))
  def shuffle(generator), do: map(list(generator), &Enum.shuffle/1)
end
