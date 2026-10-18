defmodule Hegel do
  @context_key :"$hegel_context"
  @test_case_key :"$hegel_test_case"

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
      import Hegel
      import Hegel.Gen
    end
  end

  defmacro check(form, options \\ [])

  defmacro check({:all, _meta, generators}, do: block) do
    {opts, generators} =
      case List.last(generators) do
        kw when is_list(kw) -> {kw, Enum.drop(generators, -1)}
        _ -> {[], generators}
      end

    _ = opts
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

  defmacro check(fun, options) do
    quote do: Hegel.check_run(unquote(fun), unquote(options))
  end

  defmacro gen({:all, _meta, generators}, do: block) do
    {opts, generators} =
      case List.last(generators) do
        kw when is_list(kw) -> {kw, Enum.drop(generators, -1)}
        _ -> {[], generators}
      end
    _ = opts
    {generator_ast, _} = Enum.reduce(Enum.reverse(generators), {block, true}, fn
      {:<-, _, [{name, _, _}, generator]}, acc ->
        {acc, terminal?} = acc
        body = Macro.prewalk(acc, fn
          {^name, _, _} -> Macro.var(name, nil)
          node -> node
        end)
        result = if terminal?, do: quote(do: Hegel.Gen.constant(unquote(body))), else: body
        quote do
          Hegel.Gen.bind(unquote(generator), fn unquote(Macro.var(name, nil)) ->
            unquote(result)
          end)
        end |> then(&{&1, false})
      _, acc -> acc
    end)
    generator_ast
  end

  defmacro property(description, second \\ [], do: block) do
    block = name_draws(block)

    cond do
      match?({:%{}, _, _}, second) ->
        context_names = for {key, _value} <- second |> elem(2), do: key
        block = Macro.prewalk(block, fn
          {name, meta, ctx} when is_atom(name) ->
            if Enum.member?(context_names, name), do: {:var!, meta, [{name, ctx, nil}]}, else: {name, meta, ctx}
          node -> node
        end)
        quote do
          @tag :hegel
          test unquote(description), unquote(second) do
            Hegel.check(fn -> unquote(block) end, [])
          end
        end

      is_list(second) and Keyword.keyword?(second) ->
        options = second

        quote do
          @tag :hegel
          test unquote(description) do
            Hegel.check(fn -> unquote(block) end, unquote(options))
          end
        end

      true ->
        quote do
          @tag :hegel
          test unquote(description), unquote(second) do
            Hegel.check(fn -> unquote(block) end, [])
          end
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
      test unquote(description) do
        Hegel.check(
          fn _test_case ->
            var!(hegel_context) = unquote(context)
            unquote(block)
          end,
          unquote(options)
        )
      end
    end
  end

  defmacro draw(generator) do
    name = Macro.to_string(generator)
    generator = normalize_generator(generator)
    quote do: :hegel.draw(:hegel.current_test_case(), unquote(name), unquote(generator))
  end

  defmacro draw(name, generator) do
    generator = normalize_generator(generator)
    quote do: :hegel.draw(:hegel.current_test_case(), unquote(name), unquote(generator))
  end

  defp normalize_generator({:{}, _meta, elements}), do: quote(do: Hegel.Gen.tuple(unquote(elements)))
  defp normalize_generator(generator), do: generator

  def check_run(fun, options \\ [])
  def check_run(fun, options) when is_function(fun, 0) do
    check_run(fn _test_case -> fun.() end, options)
  end

  def check_run(fun, options) when is_function(fun, 1) do
    ensure_not_nested!()
    {context_options, engine_options} = split_context_options(options)
    property = with_context(fun, context_options)
    :hegel.check(property, Hegel.Options.validate(engine_options))
  end

  def run(fun, options \\ [])
  def run(fun, options) when is_function(fun, 0) do
    run(fn _test_case -> fun.() end, options)
  end

  def run(fun, options) when is_function(fun, 1) do
    {context_options, engine_options} = split_context_options(options)
    :hegel.run(with_context(fun, context_options), Hegel.Options.validate(engine_options))
  end

  def reproduce(fun, blob, options \\ [])
  def reproduce(fun, blob, options) when is_function(fun, 0) do
    reproduce(fn _test_case -> fun.() end, blob, options)
  end

  def reproduce(fun, blob, options) when is_function(fun, 1) do
    {context_options, engine_options} = split_context_options(options)
    :hegel.reproduce(with_context(fun, context_options), blob, Hegel.Options.validate(engine_options))
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

  @doc "Returns the context created for the current generated case."
  @spec context() :: map()
  def context do
    case {Process.get(@test_case_key), Process.get(@context_key)} do
      {nil, _context} ->
        raise RuntimeError, "Hegel.context/0 called outside a property case"

      {_test_case, context} when is_map(context) ->
        context

      {_test_case, nil} ->
        raise RuntimeError, "Hegel.context/0 called without per-case setup"
    end
  end

  defp split_context_options(options) when is_list(options) do
    {setup, options} = Keyword.pop(options, :setup)
    {teardown, options} = Keyword.pop(options, :teardown)
    {%{setup: setup, teardown: teardown}, options}
  end

  defp split_context_options(options) when is_map(options) do
    {setup, options} = Map.pop(options, :setup)
    {teardown, options} = Map.pop(options, :teardown)
    {%{setup: setup, teardown: teardown}, options}
  end

  defp ensure_not_nested! do
    if Process.get(@test_case_key) != nil do
      raise RuntimeError, "nested Hegel.check is not allowed inside a property case"
    end
  end

  defp with_context(fun, %{setup: setup, teardown: teardown}) do
    validate_setup(setup)
    validate_teardown(teardown)

    fn test_case ->
      context = setup_context(setup)
      Process.put(@context_key, context)

      on_cleanup(fn ->
        try do
          if is_function(teardown, 1), do: teardown.(context)
        after
          Process.delete(@context_key)
        end
      end)

      fun.(test_case)
    end
  end

  defp setup_context(nil), do: %{}

  defp setup_context(setup) when is_function(setup, 0) do
    case setup.() do
      context when is_map(context) -> context
      other -> raise ArgumentError, "Hegel setup must return a map, got: #{inspect(other)}"
    end
  end

  defp setup_context(other) do
    raise ArgumentError, "Hegel setup must be a zero-arity function, got: #{inspect(other)}"
  end

  defp validate_setup(nil), do: :ok
  defp validate_setup(setup) when is_function(setup, 0), do: :ok

  defp validate_setup(setup) do
    raise ArgumentError, "Hegel setup must be a zero-arity function, got: #{inspect(setup)}"
  end

  defp validate_teardown(nil), do: :ok
  defp validate_teardown(teardown) when is_function(teardown, 1), do: :ok

  defp validate_teardown(teardown) do
    raise ArgumentError,
      "Hegel teardown must be a one-arity function, got: #{inspect(teardown)}"
  end

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
