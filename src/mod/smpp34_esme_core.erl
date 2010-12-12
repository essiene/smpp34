-module(smpp34_esme_core).
-behaviour(gen_server).

-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("../util.hrl").

-define(SOCK_OPTS, [binary, {packet, raw}, {active, once}]).

-record(st_esmecore, {owner, mref,
			 tx, tx_mref, 
		     rx, rx_mref,
             log, log_mref,
			 params, socket}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/4, stop/1, send/2, send/3, send/4, deliver/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Owner, Host, Port, Logger) ->
  gen_server:start_link(?MODULE, [Owner, Host, Port, Logger], []).

stop(Pid) ->
	gen_server:call(Pid, stop).

send(Pid, Body) ->
	send(Pid, ?ESME_ROK, Body).

send(Pid, Status, Body) ->
	gen_server:call(Pid, {tx, Status, Body}).

send(Pid, Status, Snum, Body) ->
	gen_server:call(Pid, {tx, Status, Snum, Body}).

deliver(Pid, Pdu) ->
    gen_server:call(Pid, {deliver, self(), Pdu}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Owner, Host, Port, Logger]) ->
	process_flag(trap_exit, true),
	Mref = erlang:monitor(process, Owner),
    LogMref = erlang:monitor(process, Logger),
	St = #st_esmecore{owner=Owner, mref=Mref, log=Logger, log_mref=LogMref},
	case gen_tcp:connect(Host, Port, ?SOCK_OPTS) of
		{error, Reason} ->
			{stop, Reason};
		{ok, Socket} ->
			St0 = St#st_esmecore{socket=Socket},

			case smpp34_tx_sup:start_child(Socket) of
				{error, Reason} ->
					{stop, Reason};
				{ok, Tx} ->
					St1 = St0#st_esmecore{tx=Tx},

					TxMref = erlang:monitor(process, Tx),
					St2 = St1#st_esmecore{tx_mref=TxMref},

					case smpp34_rx_sup:start_child(Tx, Socket) of
						{error, Reason} ->
							{stop, Reason};
						{ok, Rx} ->
							St3 = St2#st_esmecore{rx=Rx},

							RxMref = erlang:monitor(process, Rx),
							St4 = St3#st_esmecore{rx_mref=RxMref},

							case smpp34_rx:controll_socket(Rx, Socket) of
								{error, Reason} ->
									{stop, Reason};
								ok ->
									{ok, St4#st_esmecore{params={Host, Port}}}
							end
					end
			end
	end.


handle_call({deliver, Rx, Pdu}, _From, #st_esmecore{rx=Rx, owner=Owner}=St) ->
  Owner ! {esme_data, self(), Pdu},
  {reply, ok, St};
handle_call({tx, Status, Body}, _From, #st_esmecore{tx=Tx}=St) ->
  {reply, catch(smpp34_tx:send(Tx, Status, Body)), St};
handle_call({tx, Status, Snum, Body}, _From, #st_esmecore{tx=Tx}=St) ->
  {reply, catch(smpp34_tx:send(Tx, Status, Snum, Body)), St};
handle_call(stop, _From, St) ->
  {stop, normal, ok, St};
handle_call(R, _From, St) ->
  {reply, {error, R}, St}.


handle_cast(_R, St) ->
  {noreply, St}.


handle_info(#'DOWN'{ref=MRef}, #st_esmecore{mref=MRef}=St) ->
  {stop, normal, St};
handle_info(#'DOWN'{ref=MRef}, #st_esmecore{tx_mref=MRef}=St) ->
  {stop, normal, St};
handle_info(#'DOWN'{ref=MRef}, #st_esmecore{rx_mref=MRef}=St) ->
  {stop, normal, St};
handle_info(_Info, St) ->
  {noreply, St}.

terminate(_, _) ->
 ok.

code_change(_OldVsn, St, _Extra) ->
  {ok, St}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
