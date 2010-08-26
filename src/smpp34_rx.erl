-module(smpp34_rx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_server).

-export([start_link/3,stop/1]).
-export([ping/1, deliver/2]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(state, {owner, mref, tx, rx, rx_mref}).

start_link(Owner, Tx, Socket) ->
    gen_server:start_link(?MODULE, [Owner, Tx, Socket], []).

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

init([Owner, Tx, Socket]) ->
	MRef = erlang:monitor(process, Owner),
	{ok, Rx} = smpp34_tcprx_sup:start_child(Socket),
	RxMref = erlang:monitor(process, Rx),
    {ok, #state{owner=Owner, mref=MRef, tx=Tx, rx=Rx, rx_mref=RxMref}}.

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

handle_info(#'DOWN'{ref=MRef, reason=R}, #state{rx_mref=MRef}=St) ->
	{stop, {tcprx, R}, St};
handle_info(#'DOWN'{ref=MRef}, #state{mref=MRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
    {noreply, St}.

terminate(_, _) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
