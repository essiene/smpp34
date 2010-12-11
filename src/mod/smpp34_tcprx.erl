-module(smpp34_tcprx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("../util.hrl").
-behaviour(gen_server).

-export([start_link/3, stop/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).


-record(st_tcprx, {owner,mref,socket,pdusink,data, send_unbind=true}).

start_link(Owner, Socket, PduSink) ->
    gen_server:start_link(?MODULE, [Owner, Socket, PduSink], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

init([Owner, Socket, PduSink]) ->
	process_flag(trap_exit, true),
	Mref = erlang:monitor(process, Owner),
    {ok, #st_tcprx{owner=Owner, mref=Mref, socket=Socket,
				   pdusink=PduSink, data = <<>>}}.

handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info({tcp, Socket, Data}, #st_tcprx{socket=Socket, data=Data0, pdusink=PduSink}=St) ->
    Data1 = <<Data0/binary,Data/binary>>,
	{_, PduList, Rest} = smpp34pdu:unpack(Data1), 
	smpp34_rx:deliver(PduSink, PduList), 
	inet:setopts(Socket, [{active, once}]), 
	{noreply, St#st_tcprx{data=Rest}};
handle_info({tcp_closed, Socket}, #st_tcprx{socket=Socket}=St) ->
    % log tcp_closed here
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info({tcp_error, Socket, _Reason}, #st_tcprx{socket=Socket}=St) ->
	% Well, I don't think it makes sense to attempt to 
	% continue when a TCP error occurs. Better bail here, so
	% the monitoring process will also bail.

    %log {tcp_error, Reason} here
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info(#'DOWN'{ref=Mref, reason=unbind}, #st_tcprx{mref=Mref}=St) ->
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info(#'DOWN'{ref=Mref, reason=unbind_resp}, #st_tcprx{mref=Mref}=St) ->
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info(#'DOWN'{ref=Mref}, #st_tcprx{mref=Mref}=St) ->
	{stop, normal, St};
handle_info(_Req, St) ->
	{noreply, St}.

terminate(_, #st_tcprx{socket=S, send_unbind=false}) ->
	catch(gen_tcp:close(S)),
    ok;
terminate(_, #st_tcprx{socket=S}) ->
	% We are the controlling_process, so the socket will be
	% closed when we exit. We have to send #unbind{} here

	% Since we're quitting, just plunk in the maximum serial number
	% untill we find a better way to interact with smpp34_tx to
	% get the valid current serial number
	Bin = smpp34pdu:pack(?ESME_ROK, ?SNUM_MAX, #unbind{}),
	catch(gen_tcp:send(S, Bin)),
	catch(gen_tcp:close(S)),
    ok.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
