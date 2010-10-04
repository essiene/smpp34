-module(gen_esme34).
-behaviour(gen_server).

-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("util.hrl").

-export([behaviour_info/1]).

-export([start/3, start/4, start_link/3, start_link/4,
        call/2, call/3, multicall/2, multicall/3,
        multicall/4, cast/2, cast/3, abcast/2, abcast/3,
        reply/2, ping/1, send/2, send/3]).


-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

-record(st_gensmpp34, {esme, esme_mref, mod, mod_st, t1, pdutx=0, pdurx=0}).


behaviour_info(callbacks) ->
    [
        {init, 1},
        {handle_call, 3},
        {handle_cast, 2},
        {handle_info, 2},
        {handle_pdu, 2},
        {terminate, 2},
        {code_change, 3}
    ];

behaviour_info(_Other) ->
    undefined.


start_link(Name, Mod, InitArgs, Options) ->
    gen_server:start_link(Name, ?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs], Options).

start_link(Mod, InitArgs, Options) ->
    gen_server:start_link(?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs], Options).

start(Name, Mod, InitArgs, Options) ->
    gen_server:start(Name, ?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs], Options).

start(Mod, InitArgs, Options) ->
    gen_server:start(?MODULE, [{'__gen_esme34_mod', Mod} | InitArgs], Options).

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

send(ServerRef, Body) ->
	send(ServerRef, ?ESME_ROK, Body).

send(ServerRef, Status, Body) ->
	gen_server:call(ServerRef, {send, Status, Body}).

% gen_server callbacks

init([{'__gen_esme34_mod', Mod} | InitArgs]) ->
    process_flag(trap_exit, true),
	% how do we monitor owner?

    case Mod:init(InitArgs) of
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
									#pdu{command_status=?ESME_ROK}} ->
										{ok, St0#st_gensmpp34{pdutx=1, pdurx=1}};
								{esme_data, Esme,
									#pdu{command_id=?GENERIC_NACK,
										command_status=Status}} ->
										{stop, {generic_nack, Status}};
								{esme_data, Esme, 
									#pdu{command_status=Status}} ->
										{stop, {bad_status, Status}}
							% This timeout should be configurable
							after 10000 ->
								{stop, timeout}
							end

                    end
            end
    end.


handle_call(ping, _From, #st_gensmpp34{t1=T1, pdutx=TxCount, pdurx=RxCount}=St) ->
    Uptime = timer:now_diff(now(), T1)/1000,
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
do_pduspec(#st_gensmpp34{esme=E, pdutx=Tx}=St, {Status, Snum, PduBody}) ->
	{ok, _} = smpp34_esme_core:send(E, Status, Snum, PduBody),
	{noreply, St#st_gensmpp34{pdutx=Tx+1}};
do_pduspec(#st_gensmpp34{esme=E, pdutx=Tx}=St, {Status, PduBody}) ->
	{ok, _} = smpp34_esme_core:send(E, Status, PduBody),
	{noreply, St#st_gensmpp34{pdutx=Tx+1}}.

