-module(smpp34_hbeat).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").
-behaviour(gen_fsm).

-export([start_link/2,stop/1, enquire_link_resp/2]).

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

enquire_link_resp(Pid, Snum) ->
    gen_fsm:send_sync_event(Pid, {enquire_link_resp, Snum, self()}).


transmit_scheduled(send_enquire_link, #st_hbeat{tx=Tx, reqs=Reqs0, 
                   resp_time=RespTime}=St0) ->
    St1 = St0#st_hbeat{tx_tref=undefined},

    {ok, Snum} = smpp34_tx:send(Tx, ?ESME_ROK, #enquire_link{}),
    T1 = erlang:now(),
    Reqs1 = [{Snum, T1}|Reqs0],

    Tref = gen_fsm:send_event_after(RespTime, {late_response, Snum}),

    {next_state, enquire_link_sent, St1#st_hbeat{reqs=Reqs1, rx_tref=Tref}};

transmit_scheduled({enquire_link_resp, Snum, Owner}, #st_hbeat{owner=Owner,
                    reqs=Reqs0, resp_time=RespTime1}=St0) ->
    T2 = erlang:now(),
    case lists:keytake(Snum, 1, Reqs0) of
        false ->
            %log response for unknown or garbage collected? request
            {next_state, transmit_scheduled, St0};
        {value, {Snum, T1}, Reqs1} ->
            St1 = St0#st_hbeat{reqs=Reqs1},

            case timer:now_diff(T1, T2) div 1000 of %convert to milliseconds from microseconds
                N when N < RespTime1 ->
                    %log response time for Snum
                    {next_state, transmit_scheduled, St1};
                N ->
                    %log response time for Snum and changing resp_time to N
                    {next_state, transmit_scheduled, St1#st_hbeat{resp_time=N}}
            end
    end;

transmit_scheduled(_E, St) ->
    {next_state, transmit_scheduled, St}.

transmit_scheduled(E, _F, St) ->
    {reply, {error, E}, transmit_scheduled, St}.


enquire_link_sent({late_response, Snum}, #st_hbeat{}) ->
    %log this
    St1 = St0#st_hbeat{rx_tref=undefined},

    Tref = gen_fsm:send_event_after(?ENQ_LNK_INTERVAL, send_enquire_link),
    {next_state, transmit_scheduled, St1#st_hbeat{tx_tref=Tref}};

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
