-module(smpp34_rx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_server).

-export([start_link/2,stop/1]).
-export([ping/1, deliver/2]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(state, {owner, monitref, tx}).

start_link(Owner, Tx) ->
    gen_server:start_link(?MODULE, [Owner, Tx], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

ping(Pid) ->
	gen_server:call(Pid, ping).

deliver(_, []) ->
	ok;
deliver(Pid, [Head|Rest]) ->
	deliver(Pid, Head),
	deliver(Pid, Rest);
deliver(Pid, Pdu) ->
	gen_server:cast(Pid, Pdu).

init([Owner, Tx]) ->
	MonitorRef = erlang:monitor(process, Owner),
    {ok, #state{owner=Owner, monitref=MonitorRef, tx=Tx}}.

handle_call(ping, _From, #state{owner=Owner, tx=Tx}=St) ->
	{reply, {pong, [{owner,Owner}, {tx,Tx}]}, St};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(#pdu{sequence_number=Snum, body=#enquire_link{}}, #state{tx=Tx}=St) ->	
	smpp34_tcptx:send(Tx, ?ESME_ROK, Snum, #enquire_link_resp{}),
	{noreply, St};
handle_cast(#pdu{sequence_number=Snum, body=#unbind{}}, #state{tx=Tx}=St) ->	
	smpp34_tcptx:send(Tx, ?ESME_ROK, Snum, #unbind_resp{}),
	{stop, unbind, St};
handle_cast(#pdu{body=#unbind_resp{}}, St) ->	
	{stop, unbind_resp, St};
handle_cast(#pdu{}=Pdu, #state{owner=Owner}=St) ->
	error_logger:info_msg("Sending pdu to owner(~p): ~p~n", [Owner, Pdu]),
	Owner ! {self(), Pdu},
	{noreply, St};
handle_cast(stop, St) ->
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
