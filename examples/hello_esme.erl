-module(hello_esme).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-behaviour(gen_esme34).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
        handle_rx/2, handle_tx/3, terminate/2, code_change/3]).

-export([start/0, start/3, stop/0, sendsms/3, ping/0]).

-record(state, {host, port, system_id, password, owner, mref}).

start() ->
	application:start(smpp34),
    gen_esme34:start({local, ?MODULE}, ?MODULE, [self(), "localhost", 10000, "mmayen", "mmayen"], [{ignore_version, true}]).

start(Host, Port, IgnoreVersion) ->
	application:start(smpp34),
    gen_esme34:start({local, ?MODULE}, ?MODULE, [self(), Host, Port, "mmayen", "mmayen"], [{ignore_version, IgnoreVersion}]).

stop() ->
    gen_esme34:cast(?MODULE, stop).

sendsms(Source, Dest, Msg) ->
    S = #pdu{body=#submit_sm{source_addr=Source, destination_addr=Dest, short_message=Msg}},
    gen_esme34:transmit_pdu(?MODULE, S, id()).

ping() ->
    gen_esme34:ping(?MODULE).

init([Owner, Host, Port, SystemId, Password]) ->
	Mref = erlang:monitor(process, Owner),
    {ok, {Host, Port, 
            #pdu{body=#bind_receiver{system_id=SystemId, password=Password}}}, 
            #state{host=Host, port=Port, system_id=SystemId, password=Password,
			owner=Owner, mref=Mref}}.

handle_tx({ok, Sn}, Extra, St) ->
	error_logger:info_msg("helo|tx|~p|ok|~p~n", [Extra, Sn]),
	{noreply, St};
handle_tx({error, Reason}, Extra, St) ->
	error_logger:info_msg("helo|tx|~p|err|~p~n", [Extra, Reason]),
	{noreply, St}.

handle_rx(#pdu{body=#deliver_sm{source_addr=Src, destination_addr=Dst, short_message=_Msg}}=Pdu, St) ->
    error_logger:info_msg("helo|rx|~p~n", [Pdu]),
    Did = id(),
    DeliverSmResp = Pdu#pdu{command_status=?ESME_ROK, body=#deliver_sm_resp{message_id=Did}},
    SubmitSm = #pdu{body=#submit_sm{source_addr=Dst, destination_addr=Src, short_message="Hello SMPP World"}},
    {tx, [{DeliverSmResp, Did}, {SubmitSm, id()}], St};

handle_rx(Pdu, St) ->
    error_logger:info_msg("helo|rx|~p~n", [Pdu]),
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

id() ->
    {A, B, C} = now(),
    lists:flatten(io_lib:format("~p~p~p", [A, B, C])).
