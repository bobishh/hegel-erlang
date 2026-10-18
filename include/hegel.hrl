-ifndef(HEGEL_HRL).
-define(HEGEL_HRL, true).
-define(DRAW(Pattern, Generator),
    Pattern = hegel:draw(hegel:current_test_case(), ??Pattern, Generator)).
-define(DRAW_SILENT(Pattern, Generator),
    Pattern = hegel:draw_silent(hegel:current_test_case(), Generator)).
%% The enclosing test's identity, which the engine reports to Antithesis as
%% the assertion `Module::Function passes properties`.
-define(HEGEL_LOCATION, {?FILE, ?LINE, ?MODULE, ?FUNCTION_NAME}).
-define(HEGEL_CHECK(Fun, Options),
    hegel:check(Fun, maps:merge(#{location => ?HEGEL_LOCATION}, Options))).
-define(HEGEL_CHECK(Fun), ?HEGEL_CHECK(Fun, #{})).
-endif.
