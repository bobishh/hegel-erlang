defmodule Hegel do
  @moduledoc """
  Property-based testing backed by Hegel's Erlang SDK.

      use Hegel

      property "reversing twice is identity" do
        xs = draw(Hegel.Gen.list(Hegel.Gen.integer()))
        assert xs |> Enum.reverse() |> Enum.reverse() == xs
      end
  """

  defmacro __using__(_options) do
    quote do
      require Hegel
      import Hegel, only: [property: 2, property: 3, property: 4, draw: 1, draw: 2]
      import Hegel, only: [check: 2, gen: 1]
      import Hegel.Gen
    end
  end

  defmacro check({:all, _meta, generators}, do: block) do
    {opts, generators} =
      case List.last(generators) do
        kw when is_list(kw) -> {kw, Enum.drop(generators, -1)}
        _ -> {[], generators}
      end

    _ = opts
    names = for {:<-, _, [{name, _, _}, _]} <- generators, do: name
    body = Macro.prewalk(block, fn
      {name, _, _} when is_atom(name) ->
        if Enum.member?(names, name), do: {:var!, [], [{name, [], nil}]}, else: {name, [], nil}
      node -> node
    end)

    body =
      Enum.reduce(Enum.reverse(generators), block, fn
        {:<-, _, [{name, _, _}, generator]}, acc ->
          variable = {:var!, [], [{name, [], nil}]}
          quote do
            unquote(variable) = Hegel.draw(unquote(generator))
            unquote(acc)
          end
        _, acc -> acc
      end)

    quote do
      Hegel.check_run(fn -> unquote(body) end, [])
    end
  end

  defmacro gen({:all, _meta, generators}) do
    {opts, generators} =
      case List.last(generators) do
        kw when is_list(kw) -> {kw, Enum.drop(generators, -1)}
        _ -> {[], generators}
      end
    _ = opts
    Enum.reduce(Enum.reverse(generators), Hegel.Gen.constant(nil), fn
      {:<-, _, [{name, _, _}, generator]}, acc ->
        body = Macro.prewalk(acc, fn
          {^name, _, _} -> {:value, [], nil}
          node -> node
        end)
        quote do
          Hegel.Gen.bind(unquote(generator), fn value -> unquote(body) end)
        end
      _, acc -> acc
    end)
  end

  defmacro check(fun, options \\ []) do
    quote do: Hegel.check_run(unquote(fun), unquote(options))
  end

  defmacro property(description, options \\ [], do: block) do
    block = name_draws(block)

    quote do
      @tag :hegel
      test unquote(description) do
        Hegel.check(fn -> unquote(block) end, unquote(options))
      end
    end
  end

  @doc "Defines a property with a per-case context expression.

  The context is evaluated inside each generated case, which makes fixture
  setup explicit and prevents state leaking between cases."
  defmacro property(description, context, options, do: block) do
    block = name_draws(block)

    quote do
      @tag :hegel
      test unquote(description), unquote(context) do
        Hegel.check(fn _test_case -> unquote(block) end, unquote(options))
      end
    end
  end

  defmacro draw(generator) do
    name = Macro.to_string(generator)
    quote do: :hegel.draw(:hegel.current_test_case(), unquote(name), unquote(generator))
  end

  defmacro draw(name, generator) do
    quote do: :hegel.draw(:hegel.current_test_case(), unquote(name), unquote(generator))
  end

  def check_run(fun, options \\ [])
  def check_run(fun, options) when is_function(fun, 0) do
    :hegel.check(fn _test_case -> fun.() end, options(options))
  end

  def check_run(fun, options) when is_function(fun, 1), do: :hegel.check(fun, Hegel.Options.validate(options))

  def run(fun, options \\ [])
  def run(fun, options) when is_function(fun, 0) do
    :hegel.run(fn _test_case -> fun.() end, options(options))
  end

  def run(fun, options) when is_function(fun, 1), do: :hegel.run(fun, Hegel.Options.validate(options))

  def reproduce(fun, blob, options \\ []) when is_function(fun, 0) do
    :hegel.reproduce(fn _test_case -> fun.() end, blob, options(options))
  end

  def assume(value), do: :hegel.assume(value)
  def reject, do: :hegel.reject()
  @doc "Records a redacted note. Pass `redact: false` only for non-sensitive values."
  def note(value, options \\ []) do
    rendered =
      if Keyword.get(options, :redact, true),
        do: "<redacted>",
        else: inspect(value, pretty: true, limit: 100)

    :hegel.note(rendered)
  end
  def event(name, value \\ true), do: :hegel.event(name, value)
  def target(value), do: :hegel.target(value)
  def target(name, value), do: :hegel.target(name, value)
  def on_cleanup(fun), do: :hegel.on_cleanup(fun)

  defp options(options) when is_list(options), do: Hegel.Options.validate(options)
  defp options(options) when is_map(options), do: options

  defp name_draws(ast) do
    Macro.prewalk(ast, fn
      {:=, meta, [left, {:draw, draw_meta, [generator]}]} ->
        name = Macro.to_string(left)
        {:=, meta, [left, {:draw, draw_meta, [name, generator]}]}

      node ->
        node
    end)
  end
end
