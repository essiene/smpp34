-module(smpp34_rx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_server).

-export([start_link/3,stop/1]).
-export([ping/1, deliver/2, controll_socket/2]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(state, {owner, mref, tx, tx_mref, rx, rx_mref, hb, hb_mref}).

start_link(Owner, Tx, Socket) ->
    gen_server:start_link(?MODULE, [Owner, Tx, Socket], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

ping(Pid) ->
	gen_server:call(Pid, ping).

controll_socket(Pid, Socket) ->
	{ok, Rx} = gen_server:call(Pid, getrx),
	gen_tcp:controlling_process(Socket, Rx).

deliver(_, []) ->
	ok;
deliver(Pid, [Head|Rest]) ->
	deliver(Pid, Head),
	deliver(Pid, Rest);
deliver(Pid, Pdu) ->
	gen_server:cast(Pid, {self(), Pdu}).

init([Owner, Tx, Socket]) ->
	process_flag(trap_exit, true),
	MRef = erlang:monitor(process, Owner),
	TxMref = erlang:monitor(process, Tx),
	case smpp34_tcprx_sup:start_child(Socket) of
		{error, Reason} ->
			{stop, Reason};
		{ok, Rx} ->
			RxMref = erlang:monitor(process, Rx),
            case smpp34_hbeat_sup:start_child(Tx) of
                {error, Reason} ->
                    {stop, Reason};
                {ok, Hb} ->
                    HbMref = erlang:monitor(process, Hb),
                    {ok, 
                        #state{owner=Owner, mref=MRef, 
                               tx=Tx, tx_mref=TxMref,
                               rx=Rx, rx_mref=RxMref,
                               hb=Hb, hb_mref=HbMref}}
             end
	end.

handle_call(getrx, _From, #state{rx=Rx}=St) ->
	{reply, {ok, Rx}, St};
handle_call(ping, _From, #state{owner=Owner, tx=Tx, rx=Rx}=St) ->
	{reply, {pong, [{owner,Owner}, {tx,Tx}, {rx, Rx}]}, St};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast({Rx, #pdu{sequence_number=Snum, body=#enquire_link{}}}, 
					#state{tx=Tx, rx=Rx}=St) ->	
	tx_send(Tx, ?ESME_ROK, Snum, #enquire_link_resp{}),
	{noreply, St};
handle_cast({Rx, #pdu{sequence_number=Snum, body=#unbind{}}}, 
					#state{tx=Tx, rx=Rx}=St) ->	
	tx_send(Tx, ?ESME_ROK, Snum, #unbind_resp{}),
	{stop, unbind, St};
handle_cast({Rx, #pdu{body=#enquire_link_resp{}}}, #state{rx=Rx, hb=Hb}=St) ->	
    smpp34_hbeat:enquire_link_resp(Hb),
    {noreply, St};
handle_cast({Rx, #pdu{body=#unbind_resp{}}}, #state{rx=Rx}=St) ->	
	{stop, unbind_resp, St};
handle_cast({Rx, #pdu{}=Pdu}, #state{owner=Owner, rx=Rx}=St) ->
	owner_send(Owner, Pdu),
	{noreply, St};
handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info(#'DOWN'{ref=MRef}, #state{tx_mref=MRef}=St) ->
	{noreply, St#state{tx=undefined, tx_mref=undefined}};
handle_info(#'DOWN'{ref=MRef}, #state{rx_mref=MRef}=St) ->
	{stop, normal, St};
handle_info(#'DOWN'{ref=MRef}, #state{hb_mref=MRef}=St) ->
	{stop, normal, St};
handle_info(#'DOWN'{ref=MRef}, #state{mref=MRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
    {noreply, St}.

terminate(_, _) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.


tx_send(undefined, _, _, _) ->
	ok;
tx_send(Tx, Status, Snum, Body) ->
	catch(smpp34_tx:send(Tx, Status, Snum, Body)).

owner_send(Owner, Pdu) ->
	Owner ! {self(), Pdu}.
