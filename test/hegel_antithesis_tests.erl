-module(hegel_antithesis_tests).
-include_lib("eunit/include/eunit.hrl").
-include("hegel.hrl").

%% Inside Antithesis the engine appends a declaration and one evaluation per
%% located run to $ANTITHESIS_OUTPUT_DIR/sdk.jsonl. ERTS keeps its own copy of
%% the environment, so os:putenv/2 never reaches the engine's getenv: each
%% case runs in a child VM started with the variable, as Antithesis does.

-define(LOCATION(Name), "{\"test/probe.erl\", 7, hegel_probe, " Name "}").

located_passing_run_reports_true_test_() ->
    {timeout, 120, fun() ->
        [Declared, Evaluated] = child(
            "ok = hegel:check(fun(TC) -> hegel:draw(TC, \"x\", hegel_gen:integer(0, 10)) end,"
            " #{test_cases => 5, location => " ?LOCATION("passing") "})"),
        ?assertMatch(#{<<"hit">> := false, <<"must_hit">> := true,
                       <<"assert_type">> := <<"always">>}, Declared),
        ?assertMatch(#{<<"hit">> := true, <<"condition">> := true}, Evaluated),
        ?assertEqual(<<"hegel_probe::passing passes properties">>, maps:get(<<"id">>, Declared)),
        ?assertEqual(#{<<"class">> => <<"hegel_probe">>, <<"function">> => <<"passing">>,
                       <<"file">> => <<"test/probe.erl">>, <<"begin_line">> => 7,
                       <<"begin_column">> => 0}, maps:get(<<"location">>, Declared))
    end}.

%% Failure replays carry no location, so a failing run evaluates once.
located_failing_run_reports_false_once_test_() ->
    {timeout, 120, fun() ->
        ?assertMatch([#{<<"hit">> := false}, #{<<"hit">> := true, <<"condition">> := false}],
            child("#{status := failed} = hegel:run(fun(TC) ->"
                  " true = hegel:draw(TC, \"x\", hegel_gen:integer(1, 10)) < 0 end,"
                  " #{test_cases => 5, location => " ?LOCATION("failing") "})"))
    end}.

unlocated_run_does_not_report_test_() ->
    {timeout, 120, fun() ->
        ?assertEqual([], child("#{status := passed} = hegel:run(fun(_) -> ok end, #{test_cases => 2})"))
    end}.

location_macro_names_the_enclosing_function_test() ->
    {File, Line, Module, Function} = opaque(?HEGEL_LOCATION),
    ?assertEqual({?FILE, ?MODULE, location_macro_names_the_enclosing_function_test},
                 {File, Module, Function}),
    ?assert(is_integer(Line) andalso Line > 0),
    ?assertEqual(ok, ?HEGEL_CHECK(fun(_TC) -> ok end, #{test_cases => 1})).

invalid_location_is_rejected_test() ->
    ?assertError({badarg, {location, bad}},
                 hegel:run(fun(_TC) -> ok end, #{test_cases => 1, location => bad})).

%% Hides a compile-time constant from the compiler's guard folding.
opaque(Value) -> binary_to_term(term_to_binary(Value)).

child(Expr) ->
    Dir = filename:join(os:getenv("TMPDIR", "/tmp"),
                        "hegel-antithesis-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(Dir),
    try
        Args = ["-noshell"] ++ lists:append([["-pa", P] || P <- code:get_path()]) ++
               ["-eval", Expr ++ ", halt(0)."],
        Port = open_port({spawn_executable, os:find_executable("erl")},
                         [{args, Args}, {env, [{"ANTITHESIS_OUTPUT_DIR", Dir}]},
                          exit_status, stderr_to_stdout, binary]),
        {0, _Output} = collect(Port, []),
        lines(Dir)
    after
        _ = file:del_dir_r(Dir)
    end.

collect(Port, Acc) ->
    receive
        {Port, {data, Data}} -> collect(Port, [Data | Acc]);
        {Port, {exit_status, Status}} -> {Status, iolist_to_binary(lists:reverse(Acc))}
    after 110000 -> error(child_timeout)
    end.

lines(Dir) ->
    case file:read_file(filename:join(Dir, "sdk.jsonl")) of
        {ok, Bin} -> [maps:get(<<"antithesis_assert">>, json:decode(L))
                      || L <- binary:split(Bin, <<"\n">>, [global]), L =/= <<>>];
        {error, enoent} -> []
    end.
