-module(smpp34_tx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("../util.hrl").
-behaviour(gen_server).

-export([start_link/2, stop/1]).
-export([send/3, send/4, ping/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).


-record(st_tx, {owner,monitref,socket,snum, snum_monitref}).

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
	process_flag(trap_exit, true),
	MonitorRef = erlang:monitor(process, Owner),
	case smpp34_snum_sup:start_child() of
		{error, Reason} ->
			{stop, Reason};
		{ok, Snum} ->
			SnumMonitRef = erlang:monitor(process, Snum),
			{ok, #st_tx{owner=Owner, monitref=MonitorRef, socket=Socket,
						   snum=Snum, snum_monitref=SnumMonitRef}}
	end.

handle_call(ping, _From, #st_tx{owner=Owner, socket=Socket, snum=Snum}=St) ->
	{reply, {pong, [{owner, Owner}, {socket, Socket}, {snum, Snum}]}, St};
handle_call({send, Status, Body}, _From, 
				#st_tx{socket=Socket, snum=Snum}=St) ->
	{ok, Num} = smpp34_snum:next(Snum),
	Bin = smpp34pdu:pack(Status, Num, Body),
	ok = gen_tcp:send(Socket, Bin),
	{reply, {ok, Num}, St};
handle_call({send, Status, Num, Body},_From, #st_tx{socket=Socket}=St)->
	Bin = smpp34pdu:pack(Status, Num, Body),
	ok = gen_tcp:send(Socket, Bin),
	{reply, {ok, Num}, St};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info(#'DOWN'{ref=MonitorRef}, #st_tx{monitref=MonitorRef}=St) ->
	{stop, normal, St};
handle_info(#'DOWN'{ref=SnumMonitRef}, #st_tx{snum_monitref=SnumMonitRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
	{noreply, St}.

terminate(_, _) ->
	ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
