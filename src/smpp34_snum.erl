-module(smpp34_snum).
-behaviour(gen_server).

-export([start_link/0,stop/1,next/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(state, {owner, count, monitref}).
-record('DOWN', {ref, type, obj, info}).

start_link(Owner) ->
    gen_server:start_link(?MODULE, [Owner], []).

stop(Pid) ->
    gen_server:cast(Pid, {self(), stop}).

next(Pid) ->
    gen_server:call(Pid, {self(), next}).


init([Owner]) ->
	MonitorRef = erlang:monitor(process, Owner),
    {ok, #state{owner=Owner, count=0, monitref=MonitorRef}}.

handle_call({Owner, next}, _From, #state{owner=Owner, count=16#7fffffff}=St) ->
    N1 = 1,
    {reply, {ok, N1}, St#state{count=N1}};
handle_call({Owner, next}, _From, #state{owner=Owner, count=N}=St) ->
    N1 = N+1,
    {reply, {ok, N1}, St#state{count=N1}};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast({Owner, stop}, #state{owner=Owner}=St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info(#'DOWN'{ref=MonitorRef}, #state{monitref=MonitorRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
    {noreply, St}.

terminate(normal, _St) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
