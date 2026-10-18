defmodule HegelTest do
  use ExUnit.Case
  import Hegel

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

    # A property that draws nothing gives the engine nothing to vary, so it
    # may run fewer cases than requested; each case it runs must pair setup,
    # body and teardown on one context.
    messages = drain([])
    setups = for {:setup, context} <- messages, do: context
    assert length(setups) in 1..3
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
