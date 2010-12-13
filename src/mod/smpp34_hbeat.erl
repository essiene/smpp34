-module(smpp34_hbeat).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("../util.hrl").
-behaviour(gen_fsm).

-export([start_link/3,stop/1, enquire_link_resp/2]).

-export([init/1,
        handle_sync_event/4,
        handle_event/3,
        handle_info/3,
        terminate/3,
        code_change/4]).

-export([transmit_scheduled/2,
         transmit_scheduled/3,
         enquire_link_sent/2,
         enquire_link_sent/3]).

-record(st_hbeat, {owner, tx, tx_mref, tx_tref, rx_tref, mref, reqs, resp_time,
                   log}).

-define(ENQ_LNK_INTERVAL, 30000).
-define(RESP_INTERVAL, 30000).

start_link(Owner, Tx, Logger) ->
    gen_fsm:start_link(?MODULE, [Owner, Tx, Logger], []).

stop(Pid) ->
    gen_fsm:send_all_state_event(Pid, stop).

enquire_link_resp(Pid, Snum) ->
    gen_fsm:sync_send_event(Pid, {enquire_link_resp, Snum, self()}).


transmit_scheduled(send_enquire_link, #st_hbeat{log=Log}=St0) ->

    {St1, Snum} = transmit_enquire_link(St0),
    St2 = schedule_late_response(St1, Snum),

    smpp34_log:debug(Log, "hbeat: EnquireLink/~p sent", [Snum]),
    {next_state, enquire_link_sent, St2};

transmit_scheduled(_E, St) ->
    {next_state, transmit_scheduled, St}.



transmit_scheduled({enquire_link_resp, Snum, Owner}, _F, #st_hbeat{owner=Owner,
                    reqs=Reqs0, resp_time=RespTime1, log=Log}=St0) ->
    T2 = erlang:now(),
    case lists:keytake(Snum, 1, Reqs0) of
        false ->
            smpp34_log:warn(Log, "hbeat: Unknown EnquireLinkResp/~p received", [Snum]),
            {reply, ok, transmit_scheduled, St0};
        {value, {Snum, T1}, Reqs1} ->
            St1 = St0#st_hbeat{reqs=Reqs1},

            case timer:now_diff(T2, T1) div 1000 of %convert to milliseconds from microseconds
                N when N < RespTime1 ->
                    smpp34_log:debug(Log, "hbeat: EnquireLinkResp/~p received in ~pms", [Snum, N]),
                    {reply, ok, transmit_scheduled, St1};
                N ->
                    %log response time for Snum and changing resp_time to N
                    smpp34_log:warn(Log, "hbeat: EnquireLinkResp/~p received in ~pms expected in ~pms", [Snum, N, RespTime1]),
                    smpp34_log:warn(Log, "hbeat: Now changing expected response time to ~pms", [N]),
                    {reply, ok, transmit_scheduled, St1#st_hbeat{resp_time=N}}
            end
    end;

transmit_scheduled(E, _F, St) ->
    {reply, {error, E}, transmit_scheduled, St}.


enquire_link_sent({late_response, Snum}, #st_hbeat{log=Log}=St) ->
    smpp34_log:warn(Log, "hbeat: EnquireLinkResp/~p is late", [Snum]),
    {next_state, transmit_scheduled, schedule_transmit(St)};

enquire_link_sent(_E, St) ->
    {next_state, enquire_link_sent, St}.



enquire_link_sent({enquire_link_resp, Snum, Owner}, _F, #st_hbeat{owner=Owner, reqs=Reqs0, log=Log}=St0) ->
    T2 = erlang:now(),
    case lists:keytake(Snum, 1, Reqs0) of
        false ->
            smpp34_log:warn(Log, "hbeat: Unknown EnquireLinkResp/~p received", [Snum]),
            {reply, ok, transmit_scheduled, schedule_transmit(St0)};
        {value, {Snum, T1}, Reqs1} ->
            N = timer:now_diff(T2, T1) div 1000, %convert to milliseconds from microseconds
            smpp34_log:debug(Log, "hbeat: EnquireLinkResp/~p received in ~pms", [Snum, N]),
            {reply, ok, transmit_scheduled, schedule_transmit(St0#st_hbeat{reqs=Reqs1})}
    end;
enquire_link_sent(E, _F, St) ->
    {reply, {error, E}, enquire_link_sent, St}.


init([Owner, Tx, Logger]) ->
	process_flag(trap_exit, true),
	Mref = erlang:monitor(process, Owner),
    TxMref = erlang:monitor(process, Tx),

    St0 = #st_hbeat{owner=Owner, tx=Tx, tx_mref=TxMref, mref=Mref, 
                    reqs=[],resp_time=?RESP_INTERVAL, log=Logger},

    St1 = schedule_transmit(St0),

    {ok, transmit_scheduled, St1}.

handle_sync_event(E, _F, State, StData) ->
    {reply, {error, E}, State, StData}.

handle_event(stop, _State, StData) ->
    {stop, normal, StData};
handle_event(_E, State, StData) ->
    {next_state, State, StData}.

handle_info(#'DOWN'{ref=MRef}, _StName, #st_hbeat{tx_mref=MRef}=St) ->
    {stop, normal, St};
handle_info(#'DOWN'{ref=MRef}, _StName, #st_hbeat{mref=MRef}=St) ->
    {stop, normal, St};
handle_info(_E, State, StData) ->
    {next_state, State, StData}.

terminate(_,_,_) ->
    ok.

code_change(_OldVsn, State, StData, _Extra) ->
    {ok, State, StData}.


schedule_transmit(#st_hbeat{}=St0) ->
    St1 = St0#st_hbeat{rx_tref=undefined},

    Tref = gen_fsm:send_event_after(?ENQ_LNK_INTERVAL, send_enquire_link),
    St1#st_hbeat{tx_tref=Tref}.

transmit_enquire_link(#st_hbeat{tx=Tx, reqs=Reqs0}=St0) ->
    St1 = St0#st_hbeat{tx_tref=undefined},

    {ok, Snum} = smpp34_tx:send(Tx, ?ESME_ROK, #enquire_link{}),

    T1 = erlang:now(),
    Reqs1 = [{Snum, T1}|Reqs0],

    {St1#st_hbeat{reqs=Reqs1}, Snum}.

schedule_late_response(#st_hbeat{resp_time=RespTime}=St, Snum) ->
    Tref = gen_fsm:send_event_after(RespTime, {late_response, Snum}),
    St#st_hbeat{rx_tref=Tref}.
