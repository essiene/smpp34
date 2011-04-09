-module(smpp34_rx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("../util.hrl").
-behaviour(gen_server).

-export([start_link/4,stop/1]).
-export([ping/1, deliver/2, controll_socket/2]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(st_rx, {owner, mref, tx, tx_mref, rx, rx_mref, hb, hb_mref, log}).

start_link(Owner, Tx, Socket, Logger) ->
    gen_server:start_link(?MODULE, [Owner, Tx, Socket, Logger], []).

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
	gen_server:call(Pid, {self(), Pdu}).

init([Owner, Tx, Socket, Logger]) ->
	process_flag(trap_exit, true),
	MRef = erlang:monitor(process, Owner),
	TxMref = erlang:monitor(process, Tx),
	case smpp34_tcprx_sup:start_child(Socket, Logger) of
		{error, Reason} ->
			{stop, Reason};
		{ok, Rx} ->
			RxMref = erlang:monitor(process, Rx),
            case smpp34_hbeat_sup:start_child(Tx, Logger) of
                {error, Reason} ->
                    {stop, Reason};
                {ok, Hb} ->
                    HbMref = erlang:monitor(process, Hb),
                    {ok, 
                        #st_rx{owner=Owner, mref=MRef, 
                               tx=Tx, tx_mref=TxMref,
                               rx=Rx, rx_mref=RxMref,
                               hb=Hb, hb_mref=HbMref,
                               log=Logger}}
             end
	end.


handle_call({Rx, #pdu{sequence_number=Snum, body=#enquire_link{}}=Pdu}, _F,
					#st_rx{tx=Tx, rx=Rx, log=Log}=St) ->	
    smpp34_log:info(Log, "rx: EnquireLink/~p received", [Snum]),
    Pdu1 = Pdu#pdu{command_status=?ESME_ROK, body=#enquire_link_resp{}},
    case tx_send(Tx, Pdu1) of
        {error, Reason} ->
            %if we can't send an enquire_link_resp, we just stop now
            smpp34_log:error(Log, "rx: EnquireLinkResp/~p NOT sent for reason: ~p", [Snum, Reason]),
            {stop, Reason, St};
        {ok, Snum} ->
            smpp34_log:info(Log, "rx: EnquireLinkResp/~p sent", [Snum]),
            {reply, ok, St}
    end;
handle_call({Rx, #pdu{body=#unbind{}}=Pdu}, _F,
					#st_rx{tx=Tx, rx=Rx, log=Log}=St) ->	
    smpp34_log:warn(Log, "rx: Unbind PDU received"),
    Pdu1 = Pdu#pdu{command_status=?ESME_ROK, body=#unbind_resp{}},
    case tx_send(Tx, Pdu1) of
        {error, Reason} ->
            %we're already going to exit, so just proceed normally but log it
            smpp34_log:warn(Log, "rx: UnbindResp NOT sent for reason: ~p", [Reason]);
        {ok, _Snum} ->
            smpp34_log:warn(Log, "rx: UnbindResp PDU sent"),
            {stop, unbind, St}
    end;
handle_call({Rx, #pdu{sequence_number=Snum, body=#enquire_link_resp{}}}, _F, #st_rx{rx=Rx, hb=Hb}=St) ->	
    ok = smpp34_hbeat:enquire_link_resp(Hb, Snum),
    {reply, ok, St};
handle_call({Rx, #pdu{body=#unbind_resp{}}}, _F, #st_rx{rx=Rx, log=Log}=St) ->	
    smpp34_log:warn(Log, "rx: UnbindResp PDU received"),
	{stop, unbind_resp, St};
handle_call({Rx, #pdu{}=Pdu}, _F, #st_rx{owner=Owner, rx=Rx}=St) ->
	ok = owner_send(Owner, Pdu),
	{reply, ok, St};
handle_call(getrx, _From, #st_rx{rx=Rx}=St) ->
	{reply, {ok, Rx}, St};
handle_call(ping, _From, #st_rx{owner=Owner, tx=Tx, rx=Rx}=St) ->
	{reply, {pong, [{owner,Owner}, {tx,Tx}, {rx, Rx}]}, St};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info(#'DOWN'{ref=MRef}, #st_rx{tx_mref=MRef}=St) ->
	{noreply, St#st_rx{tx=undefined, tx_mref=undefined}};
handle_info(#'DOWN'{ref=MRef, reason=R}, #st_rx{rx_mref=MRef, log=Log}=St) ->
    smpp34_log:warn(Log, "rx: tcprx is down: ~p", [R]),
	{stop, normal, St};
handle_info(#'DOWN'{ref=MRef, reason=R}, #st_rx{hb_mref=MRef, log=Log}=St) ->
    smpp34_log:warn(Log, "rx: hbeat is down: ~p", [R]),
	{stop, normal, St};
handle_info(#'DOWN'{ref=MRef}, #st_rx{mref=MRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
    {noreply, St}.

terminate(_, _) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.


tx_send(undefined, _) ->
	ok;
tx_send(Tx, Pdu) ->
    smpp34_tx:send(Tx, Pdu). % think more globally with handling of timeouts

owner_send(Owner, Pdu) ->
    smpp34_esme_core:deliver(Owner, Pdu).
