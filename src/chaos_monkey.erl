%% @author Daniel Luna <daniel@lunas.se>
%% @copyright 2012 Daniel Luna
%% @doc 
-module(chaos_monkey).
-author('Daniel Luna <daniel@lunas.se>').
-behaviour(gen_server).

%% API
-export([start/0]).
-export([start_link/0]).

-export([kill/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {}).

start() ->
    application:start(?MODULE).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

kill() ->
    gen_server:call(?SERVER, kill, infinity).

init([]) ->
    random:seed(now()),
    {ok, #state{}}.

handle_call(kill, _From, State) ->
    NewState = kill_something(State),
    Reply = ok,
    {reply, Reply, NewState}.

handle_cast(kill, State) ->
    NewState = kill_something(State),
    {noreply, NewState}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

kill_something(State = #state{}) ->
    Pid = random_process(),
    Name =
        case erlang:process_info(Pid, registered_name) of
            [] -> "not_named";
            {registered_name, Reg} -> Reg
        end,
    App =
        case application:get_application(Pid) of
            {ok, A} -> A;
            undefined -> undefined
        end,
    IsSystemProcess = pman_process:is_system_process(Pid),
    IsSystemApp = lists:member(App, [kernel, chaos_monkey]),
    case IsSystemProcess orelse IsSystemApp of
        true ->
            error_logger:info_msg(
              "Cannot kill process ~p belonging to ~p (~s)",
                                  [Pid, App, Name]),
            kill_something(State);
        false ->
            error_logger:info_msg("About to kill ~p from ~p (~s)",
                                  [Pid, App, Name]),
            erlang:monitor(process, Pid),
            exit(Pid, im_killing_you),
            DeathReason =
                receive
                    {'DOWN', _, process, Pid, Reason} ->
                        Reason
                after 500 ->
                        exit(Pid, kill),
                        receive
                            {'DOWN', _, process, Pid, Reason} ->
                                Reason
                        end
                end,
            error_logger:info_msg("~p died because of ~p",
                                  [Pid, DeathReason]),
            State
    end.

random_process() ->
    Ps = erlang:processes(),
    lists:nth(random:uniform(length(Ps)), Ps).
