-module(smpp34_esme).
-behaviour(gen_fsm).
-include("util.hrl").

-record(st, {esme, esme_mref, pduq, recvq, close_reason}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([connect/2, close/1, send/2, send/3, recv/1, recv/2]).

%% ------------------------------------------------------------------
%% gen_fsm Function Exports
%% ------------------------------------------------------------------
-export([init/1, open/2, closed/2, open/3, closed/3, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

connect(Host, Port) ->
  gen_fsm:start_link(?MODULE, [Host, Port], []).

close(Pid) ->
	gen_fsm:sync_send_event(Pid, close).

send(Pid, Body) ->
	gen_fsm:sync_send_event(Pid, {send, Body}).

send(Pid, Status, Body) ->
	gen_fsm:sync_send_event(Pid, {send, Status, Body}).

recv(Pid) ->
	% by default block forever till response comes back
	recv(Pid, infinity).

recv(Pid, Timeout) ->
	case catch(gen_fsm:sync_send_event(Pid, {recv, Timeout}, Timeout)) of
		{'EXIT', {R, _}} ->
			{error, R};
		Other ->
			Other
	end.

%% ------------------------------------------------------------------
%% gen_fsm States
%% ------------------------------------------------------------------

		

open(_Event, St) ->
  {next_state, open, St}.
 
closed(_Event, St) ->
  {next_state, closed, St}.

open(close, _F, #st{esme=E}=St) ->
  {reply, smpp34_esme_core:stop(E), closed, St};
open({send, Body}, _F, #st{esme=E}=St) ->
  {reply, smpp34_esme_core:send(E, Body), open, St};
open({send, Status, Body}, _F, #st{esme=E}=St) ->
  {reply, smpp34_esme_core:send(E, Status, Body), open, St};
open({recv, Timeout}, From, St) ->
	Item = dkq:item(Timeout, From),
	do_recv(St, open, Item);
open(_Event, _From, St) ->
  {reply, {error, _Event}, open, St}.

closed(_Event, _From, #st{close_reason=undefined}=St) ->
  {reply, {error, closed}, closed, St};
closed(_Event, _From, #st{close_reason={error, R}}=St) ->
  {reply, {error, R}, closed, St};
closed(_Event, _From, #st{close_reason=R}=St) ->
  {reply, {error, R}, closed, St}.


%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------

init([Host, Port]) ->
	case smpp34_esme_core_sup:start_child(Host, Port) of
		{ok, Esme} ->
			Mref = erlang:monitor(process, Esme),
			PduQ = queue:new(),
			RecvQ = dkq:new(),
			St = #st{esme=Esme, esme_mref=Mref, pduq=PduQ, recvq=RecvQ},
			{ok, open, St};
		{error, Reason} ->
			{stop, Reason}
	end.


handle_event(_Event, StateName, St) ->
  {next_state, StateName, St}.


handle_sync_event(_Event, _From, StateName, St) ->
  {reply, ok, StateName, St}.


handle_info({esme_data, E, Pdu}, StateName, #st{esme=E}=St) ->
  do_pdu_recv(St, StateName, Pdu);
handle_info(#'DOWN'{ref=MRef, reason=R}, StateName, #st{esme_mref=MRef}=St) ->
  % when esme_core dies, keep a response for any caller that may be 
  % recv'ing, especially important if timeout is infinity. So they don't
  % wait forever. This way, EVERY RECV WILL ALWAYS GET A RESPONSE
  do_pdu_recv(St, StateName, R),
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


do_recv(#st{pduq=PduQ, recvq=RecvQ}=St, StateName, Item) ->
	case queue:out(PduQ) of
		{{value, Data}, PduQ1} ->
			{reply, {ok, Data}, StateName, St#st{pduq=PduQ1}};
		{empty, PduQ} ->
			RecvQ1 = dkq:in(Item, RecvQ),
			{next_state, StateName, St#st{recvq=RecvQ1}}
	end.

do_pdu_recv(#st{pduq=PduQ, recvq=RecvQ}=St, StateName, Pdu) ->
	case dkq:out(RecvQ) of
		{empty, RecvQ} ->
			PduQ1 = queue:in(Pdu, PduQ),
			{next_state, StateName, St#st{pduq=PduQ1}};
		{{value, From}, RecvQ1} ->
			gen_fsm:reply(From, {ok, Pdu}),
			{next_state, StateName, St#st{recvq=RecvQ1}};
		{{decayed, _}, RecvQ1} ->
			St1 = St#st{recvq=RecvQ1},
			do_pdu_recv(St1, StateName, Pdu)
	end.
			
