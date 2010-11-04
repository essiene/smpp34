-module(smpp34_hbeat).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_server).

-export([start_link/2,stop/1, enquire_link_resp/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

-record(st_hbeat, {owner, tx, tx_tref, rx_tref, monitref}).

-define(ENQ_LNK_INTERVAL, 30000).
-define(RESP_INTERVAL, 30000).

start_link(Owner, Tx) ->
    gen_server:start_link(?MODULE, [Owner, Tx], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

enquire_link_resp(Pid) ->
    gen_server:call(Pid, {enquire_link_resp, self()}).


init([Owner, Tx]) ->
	process_flag(trap_exit, true),
	MonitorRef = erlang:monitor(process, Owner),
    {ok, #st_hbeat{owner=Owner, tx=Tx, monitref=MonitorRef}, 500}.

handle_call({enquire_link_resp, Owner}, _F, #st_hbeat{owner=Owner}=St0) ->
    St1 = sched_enquire_link(St0),
    {reply, ok, St1};
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info(timeout, St0) ->
    St1 = send_enquire_link(St0),
    {noreply, St1};
handle_info({timeout, TxRef, heartbeat}, #st_hbeat{tx_tref=TxRef}=St0) ->
    St1 = send_enquire_link(St0),
    {noreply, St1};
handle_info({timeout, RxRef, no_response}, #st_hbeat{rx_tref=RxRef}=St) ->
    {stop, enquire_link_fail, St};
handle_info(#'DOWN'{ref=MonitorRef}, #st_hbeat{monitref=MonitorRef}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
    {noreply, St}.

terminate(_, _) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.

send_enquire_link(#st_hbeat{tx=Tx}=St0) ->
    catch(smpp34_tx:send(Tx, ?ESME_ROK, #enquire_link{})),
    RxRef = erlang:start_timer(?RESP_INTERVAL, self(), no_response),
    St0#st_hbeat{rx_tref=RxRef, tx_tref=undefined}.

sched_enquire_link(#st_hbeat{rx_tref=RxRef}=St0) ->
    erlang:cancel_timer(RxRef),
    TxRef = erlang:start_timer(?ENQ_LNK_INTERVAL, self(), heartbeat),
    St0#st_hbeat{tx_tref=TxRef, rx_tref=undefined}.


