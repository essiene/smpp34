-module(smpp34_esme).
-behaviour(gen_fsm).

-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").

-define(ETS_OPTS, [ordered_set, private, {keypos, 2}]).
-define(SOCK_OPTS, [binary, {packet, raw}, {active, once}]).

-record(st, {tx, tx_mref, 
		     rx, rx_mref,
			 ets, params,
			 socket,
			 close_reason}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([connect/2, close/1]).

%% ------------------------------------------------------------------
%% gen_fsm Function Exports
%% ------------------------------------------------------------------

-export([init/1, closed/2, closed/3, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

connect(Host, Port) ->
  gen_fsm:start(?MODULE, [Host, Port], []).

close(Pid) ->
	gen_fsm:sync_send_all_state_event(Pid, close).

%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------

init([Host, Port]) ->
	process_flag(trap_exit, true),
	St = #st{},
	case gen_tcp:connect(Host, Port, ?SOCK_OPTS) of
		{error, Reason} ->
			{stop, Reason};
		{ok, Socket} ->
			St0 = St#st{socket=Socket},

			case smpp34_tx_sup:start_child(Socket) of
				{error, Reason} ->
					{stop, Reason};
				{ok, Tx} ->
					St1 = St0#st{tx=Tx},

					TxMref = erlang:monitor(process, Tx),
					St2 = St1#st{tx_mref=TxMref},

					case smpp34_rx_sup:start_child(Tx, Socket) of
						{error, Reason} ->
							{stop, Reason};
						{ok, Rx} ->
							St3 = St2#st{rx=Rx},

							RxMref = erlang:monitor(process, Rx),
							St4 = St3#st{rx_mref=RxMref},

							case smpp34_rx:controll_socket(Rx, Socket) of
								{error, Reason} ->
									{stop, Reason};
								ok ->
									Ets = ets:new(pdus, ?ETS_OPTS),
									{ok, open, St4#st{ets=Ets, params={Host, Port}}}
							end
					end
			end
	end.
 
closed(_Event, St) ->
  {next_state, closed, St}.

closed(_Event, _From, St) ->
  {reply, {error, closed}, closed, St}.

handle_event(_Event, StateName, St) ->
  {next_state, StateName, St}.

handle_sync_event(close, _From, closed, St) ->
	{reply, {error, closed}, closed, St};
handle_sync_event(close, _From, _, St) ->
	do_stop(close, St),
	{reply, ok, closed, St#st{close_reason=closed}};
handle_sync_event(_Event, _From, StateName, St) ->
  {reply, ok, StateName, St}.

handle_info({Rx, Pdu}, StateName, #st{rx=Rx}=St) ->
  error_logger:info_msg("ESME PDU> ~p~n", [Pdu]),
  {next_state, StateName, St};
handle_info(#'DOWN'{ref=MRef, reason=R}, _, #st{tx_mref=MRef}=St) ->
  do_stop(tx, St),
  {next_state, closed, St#st{close_reason=R}};
handle_info(#'DOWN'{ref=MRef, reason=R}, _, #st{rx_mref=MRef}=St) ->
  do_stop(rx, St),
  {next_state, closed, St#st{close_reason=R}};
handle_info(_Info, StateName, St) ->
  {next_state, StateName, St}.

terminate(_, _, _) ->
 ok.

code_change(_OldVsn, StateName, St, _Extra) ->
  {ok, StateName, St}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

do_stop(close, #st{tx=Tx, rx=Rx}) ->
	catch(smpp34_tx:stop(Tx)),
	catch(smpp34_rx:stop(Rx));
do_stop(rx, #st{tx=Tx}) ->
	catch(smpp34_tx:stop(Tx));
do_stop(tx, #st{socket=S}) ->
	catch(gen_tcp:close(S)).
