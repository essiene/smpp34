-module(gen_esme34).
-behaviour(gen_server).

-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").

-export([behaviour_info/1]).

-export([start/3, start/4, start_link/3, start_link/4,
        call/2, call/3, multicall/2, multicall/3,
        multicall/4, cast/2, cast/3, abcast/2, abcast/3,
        reply/2, ping/1, transmit_pdu/2, transmit_pdu/3, transmit_pdu/4]).


-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

-record(st_gensmpp34, {esme, esme_mref, mod, mod_st, t1, pdutx=0, pdurx=0}).


behaviour_info(callbacks) ->
    [
        {init, 1},
        {handle_call, 3},
        {handle_cast, 2},
        {handle_info, 2},
        {handle_rx, 2},
        {handle_tx, 3},
        {terminate, 2},
        {code_change, 3}
    ];

behaviour_info(_Other) ->
    undefined.


start_link(Name, Mod, InitArgs, Options) ->
    {GenEsme34Opts, Options1} = gen_esme34_options(Options),
    InitArgs1 = lists:append([InitArgs, GenEsme34Opts]),
    gen_server:start_link(Name, ?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs1], Options1).

start_link(Mod, InitArgs, Options) ->
    {GenEsme34Opts, Options1} = gen_esme34_options(Options),
    InitArgs1 = lists:append([InitArgs, GenEsme34Opts]),
    gen_server:start_link(?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs1], Options1).

start(Name, Mod, InitArgs, Options) ->
    {GenEsme34Opts, Options1} = gen_esme34_options(Options),
    InitArgs1 = lists:append([InitArgs, GenEsme34Opts]),
    gen_server:start(Name, ?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs1], Options1).

start(Mod, InitArgs, Options) ->
    {GenEsme34Opts, Options1} = gen_esme34_options(Options),
    InitArgs1 = lists:append([InitArgs, GenEsme34Opts]),
    gen_server:start(?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs1], Options1).

call(ServerRef, Request) ->
    gen_server:call(ServerRef, Request).

call(ServerRef, Request, Timeout) ->
    gen_server:call(ServerRef, Request, Timeout).

multicall(Name, Request) ->
    gen_server:multicall(Name, Request).

multicall(Nodes, Name, Request) ->
    gen_server:multicall(Nodes, Name, Request).

multicall(Nodes, Name, Request, Timeout) ->
    gen_server:multicall(Nodes, Name, Request, Timeout).

cast(ServerRef, Request) ->
    gen_server:cast(ServerRef, Request).

cast(ServerRef, Request, Timeout) ->
    gen_server:cast(ServerRef, Request, Timeout).

abcast(Name, Request) ->
    gen_server:abcast(Name, Request).

abcast(Nodes, Name, Request) ->
    gen_server:abcast(Nodes, Name, Request).

reply(Client, Reply) ->
    gen_server:reply(Client, Reply).

ping(ServerRef) ->
    gen_server:call(ServerRef, ping).

transmit_pdu(ServerRef, Body) ->
    transmit_pdu(ServerRef, Body, undefined).

transmit_pdu(ServerRef, Body, Extra) ->
	transmit_pdu(ServerRef, ?ESME_ROK, Body, Extra).

transmit_pdu(ServerRef, Status, Body, Extra) ->
	ServerRef ! {'$transmit_pdu', Status, Body, Extra},
    ok.

% gen_server callbacks

init([{'__gen_esme34_mod', Mod} | InitArgs]) ->
    process_flag(trap_exit, true),
	% how do we monitor owner?

    {GenEsme34Opts, InitArgs1} = gen_esme34_options(InitArgs),
    BindRespTimeout = proplists:get_value(bind_resp_timeout, GenEsme34Opts, 10000),
    IgnoreVersion = proplists:get_value(ignore_version, GenEsme34Opts, false),

    case Mod:init(InitArgs1) of
        ignore ->
            ignore;
        {stop, Reason} ->
            {stop, Reason};
        {ok, {Host, Port, BindPdu}, ModSt} ->
			St = #st_gensmpp34{mod=Mod, mod_st=ModSt},

            case smpp34_esme_core_sup:start_child(Host, Port) of
                {error, Reason} ->
                    {stop, Reason};
                {ok, Esme} -> 
					Mref = erlang:monitor(process, Esme),
                    St0 = St#st_gensmpp34{t1=now(), esme=Esme, esme_mref=Mref},

					case smpp34_esme_core:send(Esme, BindPdu) of
						{error, Reason} ->
							{stop, Reason};
						{ok, _S} ->
							receive
								{esme_data, Esme,
									#pdu{command_id=?GENERIC_NACK,
										command_status=Status}} ->
										{stop, {generic_nack, ?SMPP_STATUS(Status)}};
								{esme_data, Esme, 
									#pdu{command_status=?ESME_ROK, body=RespBody}} ->
                                        St1 = St0#st_gensmpp34{pdutx=1, pdurx=1},
                                        process_bind_resp(St1, BindPdu, RespBody, IgnoreVersion);
								{esme_data, Esme, 
									#pdu{command_status=Status}} ->
										{stop, ?SMPP_STATUS(Status)}
							after BindRespTimeout ->
								{stop, timeout}
							end

                    end
            end
    end.


handle_call(ping, _From, #st_gensmpp34{t1=T1, pdutx=TxCount, pdurx=RxCount}=St) ->
    Uptime = timer:now_diff(now(), T1)/1000000,
    {reply, {pong, [{uptime, Uptime}, {txpdu, TxCount}, {rxpdu, RxCount}]}, St};

handle_call(Request, From, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St) ->
    case Mod:handle_call(Request, From, ModSt) of 
        {reply, Reply, ModSt1} ->
            {reply, Reply, St#st_gensmpp34{mod_st=ModSt1}};
        {reply, Reply, ModSt1, hibernate} ->
            {reply, Reply, St#st_gensmpp34{mod_st=ModSt1}, hibernate};
        {reply, Reply, ModSt1, Timeout} ->
            {reply, Reply, St#st_gensmpp34{mod_st=ModSt1}, Timeout};
        {noreply, ModSt1} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}};
        {noreply, ModSt1, hibernate} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, hibernate};
        {noreply, ModSt1, Timeout} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, Timeout};
        {stop, Reason, ModSt1} ->
            {stop, Reason, St#st_gensmpp34{mod_st=ModSt1}};
        {stop, Reason, Reply, ModSt1} ->
            {stop, Reason, Reply, St#st_gensmpp34{mod_st=ModSt1}}
    end.

handle_cast(Request, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St) ->
    case Mod:handle_cast(Request, ModSt) of
        {noreply, ModSt1} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}};
        {noreply, ModSt1, hibernate} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, hibernate};
        {noreply, ModSt1, Timeout} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, Timeout};
        {stop, Reason, ModSt1} ->
            {stop, Reason, St#st_gensmpp34{mod_st=ModSt1}}
    end.


handle_info({'$transmit_pdu', Status, Body, Extra}, #st_gensmpp34{esme=Esme}=St) ->
	Reply = smpp34_esme_core:send(Esme, Status, Body),
    handle_tx(Reply, Extra, St);


handle_info({esme_data, Esme, Pdu}, #st_gensmpp34{mod=Mod, mod_st=ModSt, esme=Esme, pdurx=Rx}=St0) ->
    St = St0#st_gensmpp34{pdurx=Rx+1},

    case Mod:handle_rx(Pdu, ModSt) of
		{tx, PduSpec, ModSt1} ->
			do_pduspec(St#st_gensmpp34{mod_st=ModSt1}, PduSpec);
        {noreply, ModSt1} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}};
        {noreply, ModSt1, hibernate} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, hibernate};
        {noreply, ModSt1, Timeout} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, Timeout};
        {stop, Reason, ModSt1} ->
            {stop, Reason, St#st_gensmpp34{mod_st=ModSt1}}
    end;
handle_info(#'DOWN'{ref=Mref, reason=R}, #st_gensmpp34{esme_mref=Mref}=St) ->
	{stop, R, St};
handle_info(Info, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St) ->
    case Mod:handle_info(Info, ModSt) of
        {noreply, ModSt1} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}};
        {noreply, ModSt1, hibernate} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, hibernate};
        {noreply, ModSt1, Timeout} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, Timeout};
        {stop, Reason, ModSt1} ->
            {stop, Reason, St#st_gensmpp34{mod_st=ModSt1}}
    end.

terminate(Reason, #st_gensmpp34{mod=Mod, mod_st=ModSt}) ->
    Mod:terminate(Reason, ModSt).

code_change(OldVsn, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St, Extra) ->
    {ok, ModSt1} = Mod:code_change(OldVsn, ModSt, Extra),
    {ok, St#st_gensmpp34{mod_st=ModSt1}}.


do_pduspec(St, []) ->
	{noreply, St};
do_pduspec(St, [H|T]) ->
	{noreply, St1} = do_pduspec(St, H),
	do_pduspec(St1, T);
do_pduspec(#st_gensmpp34{esme=E}=St, {Status, Snum, PduBody, Extra}) ->
	Reply = smpp34_esme_core:send(E, Status, Snum, PduBody),
    handle_tx(Reply, Extra, St);
do_pduspec(#st_gensmpp34{esme=E}=St, {Status, PduBody, Extra}) ->
	Reply = smpp34_esme_core:send(E, Status, PduBody),
    handle_tx(Reply, Extra, St).

handle_tx(Reply, Extra, #st_gensmpp34{mod=Mod, pdutx=Tx, mod_st=ModSt}=St0) ->
	St = St0#st_gensmpp34{pdutx=Tx+1},

    case Mod:handle_tx(Reply, Extra, ModSt) of 
        {noreply, ModSt1} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}};
        {noreply, ModSt1, hibernate} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, hibernate};
        {noreply, ModSt1, Timeout} ->
            {noreply, St#st_gensmpp34{mod_st=ModSt1}, Timeout};
        {stop, Reason, ModSt1} ->
            {stop, Reason, St#st_gensmpp34{mod_st=ModSt1}}
    end.


gen_esme34_options(Options) ->
    gen_esme34_options(Options, [], []).


gen_esme34_options([], Accm, Others) ->
    {lists:reverse(Accm), lists:reverse(Others)};
gen_esme34_options([{ignore_version, _}=H|T], Accm, Others) ->
    gen_esme34_options(T, [H|Accm], Others);
gen_esme34_options([ignore_version=H|T], Accm, Others) ->
    gen_esme34_options(T, [H|Accm], Others);
gen_esme34_options([{bind_resp_timeout, _}=H|T], Accm, Others) ->
    gen_esme34_options(T, [H|Accm], Others);
gen_esme34_options([H|T], Accm, Others) ->
    gen_esme34_options(T, Accm, [H|Others]).

process_bind_resp(St, #bind_receiver{}, #bind_receiver_resp{}, true) ->
    {ok, St};
process_bind_resp(St, #bind_receiver{}, #bind_receiver_resp{sc_interface_version=?VERSION}, false) ->
    {ok, St};
process_bind_resp(_, #bind_receiver{}, #bind_receiver_resp{sc_interface_version=Version}, false) ->
    {stop, {bad_smpp_version, ?SMPP_VERSION(Version)}};
process_bind_resp(St, #bind_transmitter{}, #bind_transmitter_resp{}, true) ->
    {ok, St};
process_bind_resp(St, #bind_transmitter{}, #bind_transmitter_resp{sc_interface_version=?VERSION}, false) ->
    {ok, St};
process_bind_resp(_, #bind_transmitter{}, #bind_transmitter_resp{sc_interface_version=Version}, false) ->
    {stop, {bad_smpp_version, ?SMPP_VERSION(Version)}};
process_bind_resp(St, #bind_transceiver{}, #bind_transceiver_resp{}, true) ->
    {ok, St};
process_bind_resp(St, #bind_transceiver{}, #bind_transceiver_resp{sc_interface_version=?VERSION}, false) ->
    {ok, St};
process_bind_resp(_, #bind_transceiver{}, #bind_transceiver_resp{sc_interface_version=Version}, false) ->
    {stop, {bad_smpp_version, ?SMPP_VERSION(Version)}}.

