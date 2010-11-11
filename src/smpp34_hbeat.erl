-module(smpp34_hbeat).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_fsm).

-export([start_link/2,stop/1, enquire_link_resp/1]).

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

-record(st_hbeat, {owner, tx, tx_tref, rx_tref, monitref, reqs, resp_time}).

-define(ENQ_LNK_INTERVAL, 30000).
-define(RESP_INTERVAL, 30000).

start_link(Owner, Tx) ->
    gen_fsm:start_link(?MODULE, [Owner, Tx], []).

stop(Pid) ->
    gen_fsm:send_all_state_event(Pid, stop).

enquire_link_resp(Pid) ->
    gen_fsm:send_sync_event(Pid, {enquire_link_resp, self()}).


transmit_scheduled(send_enquire_link, #st_hbeat{tx=Tx, reqs=Reqs0, 
                   resp_time=RespTime}=St0) ->
    St1 = St0#st_hbeat{tx_tref=undefined},

    {ok, Snum} = smpp34_tx:send(Tx, ?ESME_ROK, #enquire_link{}),
    T1 = erlang:now(),
    Reqs1 = [{Snum, T1}|Reqs0],

    Tref = gen_fsm:send_event_after(RespTime, {late_response, Snum}),

    {next_state, enquire_link_sent, St1#st_hbeat{reqs=Reqs1, rx_tref=Tref}};

transmit_scheduled(_E, St) ->
    {next_state, transmit_scheduled, St}.

transmit_scheduled(E, _F, St) ->
    {reply, {error, E}, transmit_scheduled, St}.

enquire_link_sent(_E, St) ->
    {next_state, enquire_link_sent, St}.

enquire_link_sent(E, _F, St) ->
    {reply, {error, E}, enquire_link_sent, St}.


init([Owner, Tx]) ->
	process_flag(trap_exit, true),
	MonitorRef = erlang:monitor(process, Owner),
    Tref = gen_fsm:send_event_after(?ENQ_LNK_INTERVAL, send_enquire_link),
    {ok, transmit_scheduled, 
        #st_hbeat{owner=Owner, tx=Tx, tx_tref=Tref, 
                  monitref=MonitorRef, reqs=[], 
                  resp_time=?RESP_INTERVAL}}.

handle_sync_event(E, _F, State, StData) ->
    {reply, {error, E}, State, StData}.

handle_event(stop, _State, StData) ->
    {stop, normal, StData};
handle_event(_E, State, StData) ->
    {next_state, State, StData}.

handle_info(_E, State, StData) ->
    {next_state, State, StData}.

terminate(_,_,_) ->
    ok.

code_change(_OldVsn, State, StData, _Extra) ->
    {ok, State, StData}.
