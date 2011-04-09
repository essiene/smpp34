-module(smpp34_tx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("../util.hrl").
-behaviour(gen_server).

-export([start_link/3, stop/1]).
-export([send/3, send/4, ping/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).


-record(st_tx, {owner,monitref,socket,snum, snum_monitref, log}).

start_link(Owner, Socket, Logger) ->
    gen_server:start_link(?MODULE, [Owner, Socket, Logger], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

send(Pid, Status, Body) ->
	gen_server:call(Pid, {send, Status, Body}).

send(Pid, Status, Snum, Body) ->
	gen_server:call(Pid, {send, Status, Snum, Body}).

ping(Pid) ->
	gen_server:call(Pid, ping).



init([Owner, Socket, Logger]) ->
	process_flag(trap_exit, true),
	MonitorRef = erlang:monitor(process, Owner),
	case smpp34_snum_sup:start_child(Logger) of
		{error, Reason} ->
			{stop, Reason};
		{ok, Snum} ->
			SnumMonitRef = erlang:monitor(process, Snum),
			{ok, #st_tx{owner=Owner, monitref=MonitorRef, socket=Socket,
						   snum=Snum, snum_monitref=SnumMonitRef,
                           log=Logger}}
	end.

handle_call(ping, _From, #st_tx{owner=Owner, socket=Socket, snum=Snum}=St) ->
	{reply, {pong, [{owner, Owner}, {socket, Socket}, {snum, Snum}]}, St};
handle_call({send, Status, Body}, _From, 
				#st_tx{socket=Socket, snum=Snum}=St) ->
	{ok, Num} = smpp34_snum:next(Snum),
	Bin = smpp34pdu:pack(Status, Num, Body),
    Reply = case catch(gen_tcp:send(Socket, Bin)) of
        ok ->
            {ok,  Num};
        {error, Reason} ->
            {error, Reason};
        {'EXIT', Reason} ->
            {error, Reason}
    end,
	{reply, Reply, St};
handle_call({send, Status, Num, Body},_From, #st_tx{socket=Socket}=St)->
	Bin = smpp34pdu:pack(Status, Num, Body),
    Reply = case catch(gen_tcp:send(Socket, Bin)) of
        ok ->
            {ok,  Num};
        {error, Reason} ->
            {error, Reason};
        {'EXIT', Reason} ->
            {error, Reason}
    end,
	{reply, Reply, St};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info(#'DOWN'{ref=MonitorRef}, #st_tx{monitref=MonitorRef}=St) ->
	{stop, normal, St};
handle_info(#'DOWN'{ref=SnumMonitRef, reason=R}, #st_tx{snum_monitref=SnumMonitRef, log=Log}=St) ->
    smpp34_log:warn(Log, "tx: snum is down: ~p", [R]),
	{stop, normal, St};
handle_info(_Req, St) ->
	{noreply, St}.

terminate(_, _) ->
	ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.


send_pdu(#st_tx{snum=Snum}=St, #pdu{sequence_number=undefined}=Pdu) ->
	{ok, Num} = smpp34_snum:next(Snum),
    send_pdu(St, Pdu#pdu{sequence_number=Num});
send_pdu(#st_tx{socket=Socket}, #pdu{sequence_number=Num}=Pdu) ->
	Bin = smpp34pdu:pack(Pdu),
    case catch(gen_tcp:send(Socket, Bin)) of
        ok ->
            {ok,  Num};
        {error, Reason} ->
            {error, Reason};
        {'EXIT', {R, }} ->
            {error, R}
    end.
