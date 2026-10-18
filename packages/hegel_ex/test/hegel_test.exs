defmodule HegelTest do
  use ExUnit.Case
  import Hegel

  test "standalone check all honors its case budget" do
    parent = self()

    check all(value <- Hegel.Gen.integer(), test_cases: 17, database: :disabled, seed: 42) do
      assert is_integer(value)
      send(parent, :case_executed)
    end

    assert length(drain([])) == 17
  end

  test "unsupported options fail before executing a case" do
    for option <- [:max_runs, :max_shrinking_steps, :test_csaes, :verbosity] do
      assert_raise ArgumentError, ~r/unsupported Hegel options/, fn ->
        Hegel.run(fn -> flunk("must not execute") end, [{option, 3}])
      end
    end
  end

  test "nested check all rejects options instead of silently ignoring them" do
    assert_raise ArgumentError, ~r/nested check all cannot accept execution options/, fn ->
      Hegel.check(
        fn ->
          check all(value <- Hegel.Gen.integer(), test_cases: 2) do
            assert is_integer(value)
          end
        end,
        test_cases: 3,
        database: :disabled
      )
    end
  end

  test "unsupported macro clauses fail during expansion" do
    for expression <- [
          "check all(x <- Hegel.Gen.integer(), x > 0), do: x",
          "check all({x, y} <- Hegel.Gen.tuple([Hegel.Gen.integer(), Hegel.Gen.integer()])), do: {x, y}",
          "gen all(x <- Hegel.Gen.integer(), x > 0), do: x",
          "gen all(x <- Hegel.Gen.integer(), max_runs: 1), do: x"
        ] do
      assert_raise ArgumentError, fn ->
        Code.eval_string("require Hegel; import Hegel; " <> expression)
      end
    end
  end

  test "facade returns a structured successful run" do
    assert %{status: :passed} =
             Hegel.run(fn -> _x = draw(Hegel.Gen.integer(0, 10)) end,
               test_cases: 3,
               database: :disabled
             )
  end

  test "setup context and teardown run independently for every case" do
    parent = self()

    assert %{status: :passed} =
             Hegel.run(
               fn ->
                 _value = draw(Hegel.Gen.integer())
                 context = Hegel.context()
                 send(parent, {:body, context})
               end,
               test_cases: 3,
               database: :disabled,
               setup: fn ->
                 context = %{id: :erlang.unique_integer([:positive])}
                 send(parent, {:setup, context})
                 context
               end,
               teardown: fn context -> send(parent, {:teardown, context}) end
             )

    messages = drain([])
    setups = for {:setup, context} <- messages, do: context
    assert length(setups) == 3
    assert setups == for({:body, context} <- messages, do: context)
    assert setups == for({:teardown, context} <- messages, do: context)
    assert length(Enum.uniq(setups)) == length(setups)
    assert_raise RuntimeError, ~r/outside a property case/, &Hegel.context/0
  end

  defp drain(acc) do
    receive do
      message -> drain([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "nested checks fail with a clear error" do
    assert_raise RuntimeError, ~r/nested Hegel\.check/, fn ->
      Hegel.check(
        fn -> Hegel.check(fn -> :ok end, test_cases: 1, database: :disabled) end,
        test_cases: 1,
        database: :disabled
      )
    end
  end

  test "check all reuses the active property case" do
    assert %{status: :passed} =
             Hegel.run(
               fn ->
                 Hegel.check all(x <- Hegel.Gen.integer(0, 10)) do
                   assert is_integer(x)
                 end
               end,
               test_cases: 2,
               database: :disabled
             )
  end

  test "shrinking pairs every independent fixture with cleanup" do
    parent = self()

    assert %{status: :failed} =
             Hegel.run(
               fn ->
                 value = draw("value", Hegel.Gen.integer(0, 1_000_000))
                 assert value < 10
               end,
               test_cases: 100,
               database: :disabled,
               seed: 42,
               setup: fn ->
                 context = %{id: make_ref()}
                 send(parent, {:setup, context})
                 context
               end,
               teardown: fn context -> send(parent, {:teardown, context}) end
             )

    messages = drain([])
    setups = for {:setup, context} <- messages, do: context
    assert length(setups) > 1
    assert setups == for({:teardown, context} <- messages, do: context)
    assert length(Enum.uniq(setups)) == length(setups)
  end

  test "teardown failures surface as cleanup errors" do
    assert_raise ErlangError, ~r/hegel_cleanup_failed/, fn ->
      Hegel.run(
        fn -> :ok end,
        test_cases: 1,
        database: :disabled,
        teardown: fn _context -> raise "cleanup failed" end
      )
    end
  end

  test "setup and teardown are applied while replaying a failure" do
    parent = self()

    result =
      Hegel.run(
        fn ->
          Hegel.note(:secret)
          raise "property failed"
        end,
        test_cases: 1,
        database: :disabled,
        seed: 17,
        setup: fn -> %{fixture: :ready} end,
        teardown: fn context -> send(parent, {:replayed_teardown, context}) end
      )

    assert %{status: :failed, failures: [%{blob: blob, output: output}]} = result
    assert output =~ "<redacted>"
    refute output =~ "secret"
    assert_receive {:replayed_teardown, %{fixture: :ready}}

    assert_raise RuntimeError, "property failed", fn ->
      Hegel.reproduce(
        fn ->
          assert Hegel.context() == %{fixture: :ready}
          Hegel.note(:secret)
          raise "property failed"
        end,
        blob,
        database: :disabled,
        setup: fn -> %{fixture: :ready} end,
        teardown: fn context -> send(parent, {:replayed_teardown, context}) end
      )
    end

    assert_receive {:replayed_teardown, %{fixture: :ready}}
  end
end

defmodule HegelPropertyContextTest do
  use ExUnit.Case
  use Hegel

  setup do
    %{fixture: %{value: :from_setup}}
  end

  # As with `test "...", context`, a bare variable binds the whole context.
  property "a named ExUnit context pattern remains available", context, test_cases: 2 do
    assert context.fixture == %{value: :from_setup}
  end

  property "map ExUnit context patterns remain available", %{fixture: fixture}, test_cases: 2 do
    assert fixture == %{value: :from_setup}
  end

  property "context patterns preserve Hegel options", %{fixture: fixture}, test_cases: 2 do
    assert fixture == %{value: :from_setup}
  end
end

defmodule HegelPropertyBudgetTest do
  use ExUnit.Case
  use Hegel

  setup context do
    counter = :atomics.new(1, [])
    expected = Map.get(context, :expected_cases, 100)
    on_exit(fn -> assert :atomics.get(counter, 1) == expected end)
    %{counter: counter}
  end

  property "default properties explore 100 cases", %{counter: counter} do
    _value = draw("value", integer())
    :atomics.add(counter, 1, 1)
  end

  @tag expected_cases: 17
  property "contextual property options control the runner", %{counter: counter},
    test_cases: 17,
    database: :disabled do
    _value = draw("value", integer())
    :atomics.add(counter, 1, 1)
  end
end
