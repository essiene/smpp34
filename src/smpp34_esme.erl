-module(smpp34_esme).
-behaviour(gen_server).
-include("util.hrl").

-record(st, {esme, esme_mref, pduq, recvq}).

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

recv(Pid) ->
	% by default block forever till response comes back
	gen_server:call(Pid, {recv, infinity}, infinity).

recv(Pid, Timeout) ->
	gen_server:call(Pid, {recv, Timeout}, Timeout).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Host, Port]) ->
	case smpp34_esme_core_sup:start_child(Host, Port) of
		{ok, Esme} ->
			Mref = erlang:monitor(process, Esme),
			PduQ = queue:new(),
			RecvQ = dkq:new(),
			St = #st{esme=Esme, esme_mref=Mref, pduq=PduQ, recvq=RecvQ},
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
handle_call({recv, Timeout}, From, St) ->
	Item = dkq:item(Timeout, From),
	do_recv(St, Item);
handle_call(R, _From, St) ->
  {reply, {error, R}, St}.

handle_cast(_R, St) ->
  {noreply, St}.

handle_info({esme_data, E, Pdu}, #st{esme=E, pduq=Q}=St) ->
  Q2 = queue:in(Pdu, Q),
  {noreply, St#st{pduq=Q2}};
handle_info(#'DOWN'{ref=MRef, reason=R}, #st{esme_mref=MRef}=St) ->
  {stop, R, St};
handle_info(_Info, St) ->
  {noreply, St}.

terminate(_, _) ->
 ok.

code_change(_OldVsn, St, _Extra) ->
  {ok, St}.

do_recv(#st{pduq=PduQ, recvq=RecvQ}=St, Item) ->
	case queue:out(PduQ) of
		{{value, Data}, PduQ1} ->
			{reply, {ok, Data}, St#st{pduq=PduQ1}};
		{empty, PduQ} ->
			RecvQ1 = dkq:in(Item, RecvQ),
			{noreply, St#st{recvq=RecvQ1}}
	end.
