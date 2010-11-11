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

-record(st_hbeat, {owner, tx, tx_tref, rx_tref, monitref}).

-define(ENQ_LNK_INTERVAL, 30000).
-define(RESP_INTERVAL, 30000).

start_link(Owner, Tx) ->
    gen_fsm:start_link(?MODULE, [Owner, Tx], []).

stop(Pid) ->
    gen_fsm:send_all_state_event(Pid, stop).

enquire_link_resp(Pid) ->
    gen_fsm:send_sync_event(Pid, {enquire_link_resp, self()}).


init([Owner, Tx]) ->
	process_flag(trap_exit, true),
	MonitorRef = erlang:monitor(process, Owner),
    {ok, #st_hbeat{owner=Owner, tx=Tx, monitref=MonitorRef}, 500}.



handle_sync_event(E, _F, State, StData) ->
    {reply, {error, E}, State, StData}.

handle_event(_E, State, StData) ->
    {next_state, State, StData}.

handle_info(_E, State, StData) ->
    {next_state, State, StData}.

terminate(_,_,_) ->
    ok.

code_change(_OldVsn, State, StData, _Extra) ->
    {ok, State, StData}.
