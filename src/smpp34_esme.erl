-module(smpp34_esme).
-behaviour(gen_fsm).

-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").

-define(ETS_OPTS, [ordered_set, private, {keypos, 2}]).
-define(SOCK_OPTS, [binary, {packet, raw}, {active, once}]).

-record(st, {tx, tx_mref, 
		     rx, rx_mref,
			 ets, params,
			 socket}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([connect/2]).

%% ------------------------------------------------------------------
%% gen_fsm Function Exports
%% ------------------------------------------------------------------

-export([init/1, closed/2, closed/3, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

connect(Host, Port) ->
  gen_fsm:start(?MODULE, [Host, Port], []).

%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------

init([Host, Port]) ->
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

handle_sync_event(_Event, _From, StateName, St) ->
  {reply, ok, StateName, St}.

handle_info({Rx, Pdu}, StateName, #st{rx=Rx}=St) ->
  error_logger:info_msg("ESME PDU> ~p~n", [Pdu]),
  {next_state, StateName, St};
handle_info(_Info, StateName, St) ->
  {next_state, StateName, St}.

terminate(_Reason, _StateName, _St) ->
  ok.

code_change(_OldVsn, StateName, St, _Extra) ->
  {ok, StateName, St}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

