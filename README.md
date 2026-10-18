# Hegel for the BEAM

An Erlang-first binding to [Hegel](https://hegel.dev), with idiomatic Elixir
and Gleam facades. All three languages share the same native engine, generator
semantics, shrinking, replay blobs, and failure model.

## Erlang

```erlang
-include_lib("hegel/include/hegel.hrl").

reverse_property_test() ->
    hegel:check(fun(_TC) ->
        ?DRAW(Xs, hegel_gen:list(hegel_gen:integer())),
        Xs = lists:reverse(lists:reverse(Xs))
    end).
```

`hegel:check/1,2` re-raises the original, shrunk exception. `hegel:run/1,2`
returns a structured result for tools and custom test adapters. A test case is
an explicit value, so helper functions and concurrent workers do not rely on
hidden global state.

## Elixir

```elixir
use Hegel

property "reverse is involutive" do
  xs = draw(Hegel.Gen.list(Hegel.Gen.integer()))
  assert xs |> Enum.reverse() |> Enum.reverse() == xs
end
```

The property macro tags tests with `:hegel`, captures useful draw names, and
preserves ExUnit assertion exceptions and stacktraces.

The default exploration budget is 100 cases (the engine may exhaust a finite
input domain earlier). Set `test_cases` on the outer `property` or `check`
runner. A standalone `check all` accepts runner options; inside a property it
only draws from the active case and rejects execution options. StreamData
options such as `max_runs` and `max_shrinking_steps` are not supported and raise
an error rather than silently changing verification strength.

`check all` and `gen all` accept simple `variable <- generator` clauses.
Unsupported patterns, filters, and generator options fail during expansion.
For destructuring use explicit draws; filter cases with `assume/1`, or build
filtered generators with `Hegel.Gen.filter/2`.

ExUnit context patterns bind once-per-test setup data. For fresh fixtures in
every generated, shrinking, and replayed case, use runner `setup: fn -> %{} end`
and `teardown: fn context -> ... end` options, or register `Hegel.on_cleanup/1`
inside the case. ExUnit `on_exit/1` runs only after the whole test.

Native run errors, including non-reproducible failures, keep `status: :error`
and retain any discovered BEAM exceptions in `failures`. `check` raises
`{:hegel_run_error, native_reason, failures}` at the original failure stack
when those diagnostics exist (otherwise the existing two-element error tuple
is retained). This path does not replay the unstable case or print its draws
or reproduction blob.

Stateful testing is exposed as `Hegel.StateMachine`; concurrent tests against
shared processes or ETS state use `Hegel.ConcurrentStateMachine`. `Hegel.Task`
clones the native test-case handle so worker processes have independent,
deterministic choice streams.

## Gleam

```gleam
import hegel/gen
import hegel/property

property.check(fn(test_case) {
  let n = property.draw(test_case, "n", gen.int())
  assert n == n
})
```

The facade uses the `hegel/property` and `hegel/gen` namespace. A root Gleam
module named `hegel` would compile to the same BEAM module as the Erlang API,
so the nested namespace keeps both packages interoperable.

## Antithesis

Hegel reports property verdicts to [Antithesis](https://antithesis.com/) when
a run knows which test it belongs to. Inside Antithesis (`ANTITHESIS_OUTPUT_DIR`
set) the engine appends one `always` assertion per located run to
`$ANTITHESIS_OUTPUT_DIR/sdk.jsonl`, named `Module::function passes properties`
and declared with `must_hit`, so the property appears in the run's report and a
counterexample fails it.

- Elixir's `property` and `check all` capture the enclosing module, test
  function, file and line automatically. Pass `location: {file, line, module,
  function}` to override it.
- Erlang names the enclosing function with `?HEGEL_LOCATION` or
  `?HEGEL_CHECK(Fun, Options)` from `hegel.hrl`, or passes
  `location => {File, Line, Module, Function}` to `hegel:check/2` and
  `hegel:run/2`.
- Runs without a location report nothing. A failing run reports once: its
  shrinking replays carry no location.

The default profile resolves to the engine's `workload` profile inside
Antithesis: urandom choices on every draw, no example database and no
wall-clock health checks. Options left unset (`derandomize`, `database`) are
left to the profile, so set them only to override it deliberately.

## Examples

Complete, runnable applications are available for each BEAM language:

- [Erlang](examples/erlang/README.md)
- [Elixir](examples/elixir/README.md)
- [Gleam](examples/gleam/README.md)

Each project includes a passing framework-integrated property and a separate
failure demo that shows shrinking and native assertion reporting.

## Development

Enter the devenv shell, then run `just test`. `just native` statically links
`hegeltest-c` into the Rustler NIF for development. Compiled NIFs are release
artifacts rather than source-controlled files; packaged releases place them
under `priv/native/<platform>`. `HEGEL_NIF_PATH` remains available for
packagers and local debugging; when it names an existing library, the Elixir
package's compiler copies it instead of running cargo, so sandboxed builds can
supply an engine built elsewhere.
