-module(hello_esme).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-behaviour(gen_esme34).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
        handle_pdu/2, terminate/2, code_change/3]).

-export([start/0, start/2, stop/0, sendsms/3, ping/0]).

-record(state, {host, port, system_id, password, owner, mref}).

start() ->
	application:start(smpp34),
    gen_esme34:start({local, ?MODULE}, ?MODULE, [self(), "localhost", 10000, "mmayen", "mmayen"], []).

start(Host, Port) ->
	application:start(smpp34),
    gen_esme34:start({local, ?MODULE}, ?MODULE, [self(), Host, Port, "mmayen", "mmayen"], []).

stop() ->
    gen_esme34:cast(?MODULE, stop).

sendsms(Source, Dest, Msg) ->
    S = #submit_sm{source_addr=Source, destination_addr=Dest, short_message=Msg},
    gen_esme34:send(?MODULE, S).

ping() ->
    gen_esme34:ping(?MODULE).

init([Owner, Host, Port, SystemId, Password]) ->
	Mref = erlang:monitor(process, Owner),
    {ok, {Host, Port, 
            #bind_receiver{system_id=SystemId, password=Password}}, 
            #state{host=Host, port=Port, system_id=SystemId, password=Password,
			owner=Owner, mref=Mref}}.

handle_pdu(#pdu{sequence_number=Snum, body=#deliver_sm{source_addr=Src, destination_addr=Dst, short_message=_Msg}}=Pdu, St) ->
    error_logger:info_msg("hello_esme ==> ~p", [Pdu]),
	DeliverSmResp = #deliver_sm_resp{message_id="foo"},
    SubmitSm = #submit_sm{source_addr=Dst, destination_addr=Src, short_message="Hello SMPP World"},
    {pdu, [{?ESME_ROK, Snum, DeliverSmResp}, {?ESME_ROK, SubmitSm}], St};

handle_pdu(Pdu, St) ->
    error_logger:info_msg("hello_esme ==> ~p", [Pdu]),
    {noreply, St}.
    
handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info({'DOWN', Mref, _, _, Reason}, #state{mref=Mref}=St) ->
	{stop, Reason, St};
handle_info(_Req, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
