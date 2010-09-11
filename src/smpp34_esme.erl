-module(smpp34_esme).
-behaviour(gen_server).
-include("util.hrl").

-record(st, {esme, esme_mref, q}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([connect/2, close/1, send/2, send/3]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

connect(Host, Port) ->
  gen_server:start(?MODULE, [Host, Port], []).

close(Pid) ->
	gen_server:call(Pid, close).

send(Pid, Body) ->
	gen_server:call(Pid, {send, Body}).

send(Pid, Status, Body) ->
	gen_server:call(Pid, {send, Status, Body}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Host, Port]) ->
	case smpp34_esme_core_sup:start_child(Host, Port) of
		{ok, Esme} ->
			Mref = erlang:monitor(process, Esme),
			Q = queue:new(),
			St = #st{esme=Esme, esme_mref=Mref, q=Q},
			{ok, St};
		{error, Reason} ->
			{stop, Reason}
	end.

handle_call(close, _F, #st{esme=E}=St) ->
  {reply, smpp34_esme_core:stop(E), St};
handle_call({send, Body}, _F, #st{esme=E}=St) ->
  {reply, smpp34_esme_core:send(E, Body), St};
handle_call({send, Status, Body}, _F, #st{esme=E}=St) ->
  {reply, smpp34_esme_core:send(E, Status, Body), St};
handle_call(R, _From, St) ->
  {reply, {error, R}, St}.

handle_cast(_R, St) ->
  {noreply, St}.

handle_info({esme_data, E, Pdu}, #st{esme=E}=St) ->
  error_logger:info_msg("PDU ==> ~p~n", [Pdu]),
  {noreply, St};
handle_info(#'DOWN'{ref=MRef, reason=R}, #st{esme_mref=MRef}=St) ->
  {stop, R, St};
handle_info(_Info, St) ->
  {noreply, St}.

terminate(_, _) ->
 ok.

code_change(_OldVsn, St, _Extra) ->
  {ok, St}.
