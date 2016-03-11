-module(escalus_fresh).
-export([story/3, story_with_config/3, create_users/2]).
-export([start/1, stop/1, clean/0]).

-type userspec() :: {atom(), integer()}.
-type config() :: escalus:config().

%% @doc
%% Run story with fresh users (non-breaking API).
%% The genererated fresh usernames will consist of the predefined {username, U} value
%% prepended to a unique, per-story suffix.
%% {username, <<"alice">>} -> {username, <<"alice32.632506">>}
-spec story(config(), [userspec()], fun()) -> any().
story(Config, UserSpecs, StoryFun) ->
    escalus:story(create_users(Config, UserSpecs), UserSpecs, StoryFun).

%% @doc
%% Run story with fresh users AND fresh config passed as first argument
%% If within a story there are references to the top-level Config object,
%% discrepancies may arise when querying this config object for user data,
%% as it will differ from the fresh config actually used by the story.
%% The story arguments can be changed from
%%
%% fresh_story(C,[..],fun(Alice, Bob) ->
%% to
%% fresh_story_with_config(C,[..],fun(FreshConfig, Alice, Bob) ->
%%
%% and any queries rewritten to use FreshConfig within this scope

-spec story_with_config(config(), [userspec()], fun()) -> any().
story_with_config(Config, UserSpecs, StoryFun) ->
    FreshConfig = create_users(Config, UserSpecs),
    escalus:story(FreshConfig, UserSpecs,
                  fun(Args) -> apply(StoryFun, [FreshConfig|Args]) end).

%% @doc
%% Create fresh users for lower-level testing (NOT escalus:stories)
%% The users are created and the config updated with their fresh usernames.
-spec create_users(config(), [userspec()]) -> config().
create_users(Config, UserSpecs) ->
    Suffix = fresh_suffix(),
    FreshSpecs = fresh_specs(Config, UserSpecs, Suffix),
    case length(FreshSpecs) == length(UserSpecs) of
        false -> error("failed to get required users"); _ -> ok end,
    FreshConfig = escalus_users:create_users(Config, FreshSpecs),
    %% The line below is not needed if we don't want to support cleaning
    ets:insert(nasty_global_table(), {Suffix, FreshConfig}),
    FreshConfig.

%%% Stateful API
%%% Required if we expect to be able to clean up autogenerated users.
start(Config) -> ensure_table_present(nasty_global_table()).
stop(_) -> nasty_global_table() ! bye.
clean() ->
    Del = fun(Conf) ->
                  Plist = proplists:get_value(escalus_users, Conf),
                  escalus_users:delete_users(Conf, Plist) end,
    [ Del(FreshConfig) || {_, FreshConfig} <- ets:tab2list(nasty_global_table()) ],
    ets:delete_all_objects(nasty_global_table()).


%%% Internals
nasty_global_table() -> escalus_fresh_db.

ensure_table_present(T) ->
    case ets:info(T) of
        undefined ->
            P = spawn(fun() -> ets:new(T, [named_table, public]),
                               receive bye -> ok end end),
            erlang:register(T, P);
        _nasty_table_is_there_well_run_with_it -> ok
    end.

fresh_specs(Config, TestedUsers, StorySuffix) ->
    AllSpecs = escalus_config:get_config(escalus_users, Config),
    [ make_fresh_username(Spec, StorySuffix)
      || Spec <- select(TestedUsers, AllSpecs) ].

make_fresh_username({N, UserConfig}, Suffix) ->
    {username, OldName} = proplists:lookup(username, UserConfig),
    NewName = << OldName/binary, Suffix/binary >>,
    {N, lists:keyreplace(username, 1, UserConfig, {username, NewName})}.

select(UserResources, FullSpecs) ->
    Fst = fun({A, _}) -> A end,
    UserNames = lists:map(Fst, UserResources),
    lists:filter(fun({Name, _}) -> lists:member(Name, UserNames) end,
                 FullSpecs).

fresh_suffix() ->
    {_, S, US} = erlang:now(),
    L = lists:flatten([integer_to_list(S rem 100), ".", integer_to_list(US)]),
    list_to_binary(L).
