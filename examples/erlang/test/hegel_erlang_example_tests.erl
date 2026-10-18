-module(hegel_erlang_example_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("hegel/include/hegel.hrl").

reverse_property_test() ->
    ?assertEqual(ok, hegel_erlang_example:reverse_property()).

%% ?HEGEL_LOCATION names the enclosing function, which the engine reports
%% to Antithesis as `Module::Function passes properties`.
location_macro_names_the_enclosing_function_test() ->
    {File, Line, Module, Function} = opaque(?HEGEL_LOCATION),
    ?assertEqual({?FILE, ?MODULE, location_macro_names_the_enclosing_function_test},
                 {File, Module, Function}),
    ?assert(is_integer(Line) andalso Line > 0),
    ?assertEqual(ok, ?HEGEL_CHECK(fun(_TC) -> ok end, #{test_cases => 1})).

%% Hides a compile-time constant from the compiler's guard folding.
opaque(Value) -> binary_to_term(term_to_binary(Value)).
