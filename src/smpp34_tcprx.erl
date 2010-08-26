-module(smpp34_tcprx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_server).

-export([start_link/3, stop/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).


-record(state, {owner,monitref,socket,pdurx,data}).

start_link(Owner, Socket, PduRx) ->
    gen_server:start_link(?MODULE, [Owner, Socket, PduRx], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

init([Owner, Socket, PduRx]) ->
	MonitorRef = erlang:monitor(process, Owner),
    {ok, #state{owner=Owner, monitref=MonitorRef, socket=Socket,
				   pdurx=PduRx, data = <<>>}}.

handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info({tcp, Socket, Data}, #state{socket=Socket, data=Data0, pdurx=PduRx}=St) ->
    Data1 = <<Data0/binary,Data/binary>>,
	{_, PduList, Rest} = smpp34pdu:unpack(Data1), 
	smpp34_pdurx:deliver(PduRx, PduList), 
	inet:setopts(Socket, [{active, once}]), 
	{noreply, St#state{data=Rest}};
handle_info({tcp_closed, Socket}, #state{socket=Socket}=St) ->
	{stop, tcp_closed, St};
handle_info({tcp_error, Socket, Reason}, #state{socket=Socket}=St) ->
	% Well, I don't think it makes sense to attempt to 
	% continue when a TCP error occurs. Better bail here, so
	% the monitoring process will also bail.

	{stop, {tcp_error, Reason}, St};
handle_info(#'DOWN'{ref=MonitorRef}, #state{monitref=MonitorRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
	{noreply, St}.

terminate(_Reason, _St) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
