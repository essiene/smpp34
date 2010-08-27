-module(smpp34_tx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_server).

-export([start_link/2, stop/1]).
-export([send/3, send/4, ping/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).


-record(state, {owner,monitref,socket,snum, snum_monitref}).

start_link(Owner, Socket) ->
    gen_server:start_link(?MODULE, [Owner, Socket], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

send(Pid, Status, Body) ->
	gen_server:call(Pid, {send, Status, Body}).

send(Pid, Status, Snum, Body) ->
	gen_server:call(Pid, {send, Status, Snum, Body}).

ping(Pid) ->
	gen_server:call(Pid, ping).



init([Owner, Socket]) ->
	MonitorRef = erlang:monitor(process, Owner),
	case smpp34_snum_sup:start_child() of
		{error, Reason} ->
			{stop, Reason};
		{ok, Snum} ->
			SnumMonitRef = erlang:monitor(process, Snum),
			{ok, #state{owner=Owner, monitref=MonitorRef, socket=Socket,
						   snum=Snum, snum_monitref=SnumMonitRef}}
	end.

handle_call(ping, _From, #state{owner=Owner, socket=Socket, snum=Snum}=St) ->
	{reply, {pong, [{owner, Owner}, {socket, Socket}, {snum, Snum}]}, St};
handle_call({send, Status, Body}, _From, 
				#state{socket=Socket, snum=Snum}=St) ->
	{ok, Num} = smpp34_snum:next(Snum),
	Bin = smpp34pdu:pack(Status, Num, Body),
	ok = gen_tcp:send(Socket, Bin),
	{reply, {ok, Num}, St};
handle_call({send, Status, Num, Body},_From, #state{socket=Socket}=St)->
	Bin = smpp34pdu:pack(Status, Num, Body),
	ok = gen_tcp:send(Socket, Bin),
	{reply, {ok, Num}, St};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info(#'DOWN'{ref=MonitorRef}, #state{monitref=MonitorRef}=St) ->
	{stop, normal, St};
handle_info(#'DOWN'{ref=SnumMonitRef}, #state{snum_monitref=SnumMonitRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
	{noreply, St}.

terminate(_Reason, _St) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
