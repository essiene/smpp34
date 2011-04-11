-module(gen_esme34).
-behaviour(gen_server).

-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").

-export([behaviour_info/1]).

-export([start/3, start/4, start_link/3, start_link/4,
        call/2, call/3, multi_call/2, multi_call/3,
        multi_call/4, cast/2, abcast/2, abcast/3,
        reply/2, ping/1, transmit_pdu/2, transmit_pdu/3,
        async_transmit_pdu/2, async_transmit_pdu/3]).


-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

-record(st_gensmpp34, {esme, esme_mref, mod, mod_st, t1, pdutx=0, pdurx=0,
                        logger, max_async_transmit=infinity, async_transmit_count=0}).


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

multi_call(Name, Request) ->
    gen_server:multi_call(Name, Request).

multi_call(Nodes, Name, Request) ->
    gen_server:multi_call(Nodes, Name, Request).

multi_call(Nodes, Name, Request, Timeout) ->
    gen_server:multi_call(Nodes, Name, Request, Timeout).

cast(ServerRef, Request) ->
    gen_server:cast(ServerRef, Request).

abcast(Name, Request) ->
    gen_server:abcast(Name, Request).

abcast(Nodes, Name, Request) ->
    gen_server:abcast(Nodes, Name, Request).

reply(Client, Reply) ->
    gen_server:reply(Client, Reply).

ping(ServerRef) ->
    gen_server:call(ServerRef, ping).


transmit_pdu(ServerRef, #pdu{}=Pdu) ->
    transmit_pdu(ServerRef, Pdu, undefined).

transmit_pdu(ServerRef, #pdu{}=Pdu, Extra) ->
    gen_server:call(ServerRef, {transmit_pdu, Pdu, Extra}).

async_transmit_pdu(ServerRef, #pdu{}=Pdu) ->
    async_transmit_pdu(ServerRef, Pdu, undefined).

async_transmit_pdu(ServerRef, #pdu{}=Pdu, Extra) ->
    gen_server:cast(ServerRef, {transmit_pdu, Pdu, Extra}).


% gen_server callbacks

init([{'__gen_esme34_mod', Mod} | InitArgs]) ->
    process_flag(trap_exit, true),
	% how do we monitor owner?

    {GenEsme34Opts, InitArgs1} = gen_esme34_options(InitArgs),
    init_stage0(Mod, InitArgs1, GenEsme34Opts).


handle_call({transmit_pdu, Pdu, Extra}, _From, #st_gensmpp34{esme=Esme}=St) ->
    Reply = smpp34_esme_core:send(Esme, Pdu),
    self() ! {handle_tx, Reply, Extra},
    {reply, ok, St};

handle_call(ping, _From, #st_gensmpp34{t1=T1, pdutx=TxCount, pdurx=RxCount}=St) ->
    UptimeS = timer:now_diff(now(), T1) div 1000000,
    Uptime = calendar:seconds_to_daystime(UptimeS),
    {reply, {pong, [{uptime, Uptime}, {txpdu, TxCount}, {rxpdu, RxCount}]}, St};

handle_call(Request, From, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St) ->
    case Mod:handle_call(Request, From, ModSt) of 
        {reply, Reply, ModSt1} ->
            {reply, Reply, St#st_gensmpp34{mod_st=ModSt1}};
        {reply, Reply, ModSt1, hibernate} ->
            {reply, Reply, St#st_gensmpp34{mod_st=ModSt1}, hibernate};
        {reply, Reply, ModSt1, Timeout} ->
            {reply, Reply, St#st_gensmpp34{mod_st=ModSt1}, Timeout};
   		{tx, PduSpec, ModSt1} ->
			do_pduspec(St#st_gensmpp34{mod_st=ModSt1}, PduSpec);
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

handle_cast({transmit_pdu, Pdu, Extra}, #st_gensmpp34{max_async_transmit=infinity,
    async_transmit_count=N}=St) ->
    self() ! {async_transmit_pdu, Pdu, Extra},
    {noreply, St#st_gensmpp34{async_transmit_count=N+1}};

handle_cast({transmit_pdu, Pdu, Extra}, #st_gensmpp34{max_async_transmit=N,
    async_transmit_count=N}=St) ->
    self() ! {handle_tx, {warning, async_transmit_overload, Pdu}, Extra},
    {noreply, St};

handle_cast({transmit_pdu, Pdu, Extra}, #st_gensmpp34{async_transmit_count=N}=St) ->
    self() ! {async_transmit_pdu, Pdu, Extra},
    {noreply, St#st_gensmpp34{async_transmit_count=N+1}};

handle_cast(Request, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St) ->
    case Mod:handle_cast(Request, ModSt) of
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
    end.


handle_info({async_transmit_pdu, Pdu, Extra}, #st_gensmpp34{esme=Esme,
    async_transmit_count=N}=St) ->
    Reply = smpp34_esme_core:send(Esme, Pdu),
    self() ! {handle_tx, Reply, Extra},
    {noreply, St#st_gensmpp34{async_transmit_count=N-1}};

handle_info({handle_tx, Reply, Extra}, St) ->
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
handle_info(#'DOWN'{ref=Mref, reason=R}, #st_gensmpp34{esme_mref=Mref, logger=Logger}=St) ->
    smpp34_log:warn(Logger, "gen_esme34: esme_core is down: ~p", [R]),
	{stop, normal, St};
handle_info(Info, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St) ->
    case Mod:handle_info(Info, ModSt) of
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
    end.

terminate(Reason, #st_gensmpp34{mod=Mod, mod_st=ModSt, logger=Logger}) ->
    Mod:terminate(Reason, ModSt),
    smpp34_log:info(Logger, "gen_esme34: Terminating with reason: ~p", [Reason]).

code_change(OldVsn, #st_gensmpp34{mod=Mod, mod_st=ModSt}=St, Extra) ->
    {ok, ModSt1} = Mod:code_change(OldVsn, ModSt, Extra),
    {ok, St#st_gensmpp34{mod_st=ModSt1}}.


do_pduspec(St, []) ->
	{noreply, St};
do_pduspec(St, [H|T]) ->
	{noreply, St1} = do_pduspec(St, H),
	do_pduspec(St1, T);
do_pduspec(#st_gensmpp34{esme=E}=St, {Pdu, Extra}) ->
	Reply = smpp34_esme_core:send(E, Pdu),
    handle_tx(Reply, Extra, St);
do_pduspec(#st_gensmpp34{esme=E}=St, Pdu) ->
	Reply = smpp34_esme_core:send(E, Pdu),
    handle_tx(Reply, undefined, St).

handle_tx(Reply, Extra, #st_gensmpp34{mod=Mod, pdutx=Tx, mod_st=ModSt}=St0) ->
	St = St0#st_gensmpp34{pdutx=Tx+1},

    case Mod:handle_tx(Reply, Extra, ModSt) of 
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
gen_esme34_options([{logger, _}=H|T], Accm, Others) ->
    gen_esme34_options(T, [H|Accm], Others);
gen_esme34_options([{max_async_transmit, _}=H|T], Accm, Others) ->
    gen_esme34_options(T, [H|Accm], Others);
gen_esme34_options([H|T], Accm, Others) ->
    gen_esme34_options(T, Accm, [H|Others]).


% Stage 0: Create the logger
init_stage0(Mod, Args, Opts) ->
    case smpp34_log_sup:start_child() of
        {error, Reason} ->
            {stop, Reason};
        {ok, Logger} ->
            St = #st_gensmpp34{logger=Logger},

            case proplists:get_value(logger, Opts, false) of
                false ->
                    init_stage1(Mod, Args, Opts, St);
                {LogModule, LogArgs} ->
                    case smpp34_log:add_logger(Logger, LogModule, LogArgs) of
                        ok ->
                            init_stage1(Mod, Args, Opts, St);
                        {error, Reason} ->
                            {stop, Reason}
                    end;
                LogModule ->
                    case smpp34_log:add_logger(Logger, LogModule, []) of
                        ok ->
                            init_stage1(Mod, Args, Opts, St);
                        {error, Reason} ->
                            {stop, Reason}
                    end
            end
    end.



% Stage 1: initialize gen_smpp34 callback module
init_stage1(Mod, Args, Opts, #st_gensmpp34{logger=Logger}=St0) ->
    MaxAsyncTrans = proplists:get_value(max_async_transmit, Opts, infinity),
        
    case Mod:init(Args) of
        ignore ->
            ignore;
        {stop, Reason} ->
            smpp34_log:error(Logger, "gen_esme34: ~p while initializing callback module", [Reason]),
            {stop, Reason};
        {ok, {_, _, _}=ConnSpec, ModSt} ->
			St1 = St0#st_gensmpp34{mod=Mod, mod_st=ModSt, max_async_transmit=MaxAsyncTrans},
            init_stage2(ConnSpec, Opts, St1)
    end.

% Stage 2: start esme_core
init_stage2({Host, Port, _}=ConnSpec, Opts, #st_gensmpp34{logger=Logger}=St0) -> 
    case smpp34_esme_core_sup:start_child(Host, Port, Logger) of 
        {error, Reason} -> 
            smpp34_log:error(Logger, "gen_esme34: ~p while starting esme_core", [Reason]),
            {stop, Reason}; 
        {ok, Esme} -> 
            Mref = erlang:monitor(process, Esme),
            St1 = St0#st_gensmpp34{t1=now(), esme=Esme, esme_mref=Mref},
            init_stage3(ConnSpec, Esme, Opts, St1)
    end.

% Stage 3: Send Bind PDU to endpoint
init_stage3({_,_,BindPdu}, Esme, Opts, #st_gensmpp34{logger=Logger}=St) -> 
    SendPdu = case BindPdu of
        #pdu{}= P ->
            P;
        Body ->
            #pdu{body=Body}
    end,
    case smpp34_esme_core:send(Esme, SendPdu) of 
        {error, Reason} -> 
            smpp34_log:error(Logger, "gen_esme34: ~p while sending Bind PDU", [Reason]),
            {stop, Reason}; 
        {ok, _S} -> 
            Timeout = proplists:get_value(bind_resp_timeout, Opts, 10000), 

            receive 
                {esme_data, Esme, Pdu} ->
                    init_stage4(Pdu, SendPdu#pdu.body, Opts, St)
             after Timeout -> 
                smpp34_log:error(Logger, "gen_esme34: Timeout (~pms) while sending Bind PDU", [Timeout]),
                {stop, timeout} 
             end
        end.

% Stage 4: Process Response Pdu Header
init_stage4(#pdu{command_id=?GENERIC_NACK, command_status=Status}, _, _, _) ->
    {stop, {generic_nack, ?SMPP_STATUS(Status)}};
init_stage4(#pdu{command_status=?ESME_ROK, body=RespBody}, BindPdu, Opts, St0) -> 
    IgnVsn= proplists:get_value(ignore_version, Opts, false),
    St1 = St0#st_gensmpp34{pdutx=1, pdurx=1}, 
    init_stage5(St1, BindPdu, RespBody, IgnVsn); 
init_stage4(#pdu{command_status=Status}, _, _, _) -> 
    {stop, ?SMPP_STATUS(Status)}.


% Stage 5: Process Response Pdu Body
init_stage5(St, #bind_receiver{}, #bind_receiver_resp{}, true) ->
    init_stage6(St);
init_stage5(St, #bind_receiver{}, #bind_receiver_resp{sc_interface_version=?VERSION}, false) ->
    init_stage6(St);
init_stage5(St, #bind_receiver{}, #bind_receiver_resp{sc_interface_version=Version}, false) ->
    init_bad_version(St, Version);
init_stage5(St, #bind_transmitter{}, #bind_transmitter_resp{}, true) ->
    init_stage6(St);
init_stage5(St, #bind_transmitter{}, #bind_transmitter_resp{sc_interface_version=?VERSION}, false) ->
    init_stage6(St);
init_stage5(St, #bind_transmitter{}, #bind_transmitter_resp{sc_interface_version=Version}, false) ->
    init_bad_version(St, Version);
init_stage5(St, #bind_transceiver{}, #bind_transceiver_resp{}, true) ->
    init_stage6(St);
init_stage5(St, #bind_transceiver{}, #bind_transceiver_resp{sc_interface_version=?VERSION}, false) ->
    init_stage6(St);
init_stage5(St, #bind_transceiver{}, #bind_transceiver_resp{sc_interface_version=Version}, false) ->
    init_bad_version(St, Version);
init_stage5(#st_gensmpp34{logger=Logger}, _, Response, _) ->
    smpp34_log:error(Logger, "gen_esme34: SMSC returned wrong response PDU - ~p", [?SMPP_PDU2CMDID(Response)]),
    {stop, {bad_bind_response, ?SMPP_PDU2CMDID(Response)}}.

% Stage 6: Any common success actions. currently, just logging
init_stage6(#st_gensmpp34{logger=Logger}=St) ->
    smpp34_log:info(Logger, "gen_esme34: Started ok"),
    {ok, St}.

init_bad_version(#st_gensmpp34{logger=Logger}, Version) ->
    V = ?SMPP_VERSION(Version),
    smpp34_log:error(Logger, "gen_esme34: SMSC returned bad SMPP version - ~p", [V]),
    {stop, {bad_smpp_version, V}}.
