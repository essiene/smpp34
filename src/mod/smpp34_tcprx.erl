-module(smpp34_tcprx).
-include_lib("smpp34pdu/include/smpp34pdu.hrl").
-include("../util.hrl").
-behaviour(gen_server).

-export([start_link/4, stop/1]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).


-record(st_tcprx, {owner,mref,socket,pdusink,data, send_unbind=true, log}).

start_link(Owner, Socket, PduSink, Logger) ->
    gen_server:start_link(?MODULE, [Owner, Socket, PduSink, Logger], []).

stop(Pid) ->
    gen_server:cast(Pid, stop).

init([Owner, Socket, PduSink, Logger]) ->
	process_flag(trap_exit, true),
	Mref = erlang:monitor(process, Owner),
    {ok, #st_tcprx{owner=Owner, mref=Mref, socket=Socket,
				   pdusink=PduSink, data = <<>>, log=Logger}}.

handle_call(Req, _From, St) ->
    {reply, {error, Req}, St}.

handle_cast(stop, St) ->
    {stop, normal, St};
handle_cast(_Req, St) ->
    {noreply, St}.

handle_info({tcp, Socket, Data}, #st_tcprx{socket=Socket, data=Data0, pdusink=PduSink, log=Log}=St) ->
    Data1 = <<Data0/binary,Data/binary>>,
	{_, PduList, Rest} = smpp34pdu:unpack(Data1), 
	case smpp34_rx:deliver(PduSink, PduList) of
        {error, timeout} ->
            smpp34_log:warn(Log, "tcprx: Receive pipeline busy. Network receive suspended for 5 seconds"),
            {noreply, St#st_tcprx{data=Rest}, 5000};
        ok -> 
            smpp34_log:debug(Log, "tcprx: Continuing network receive"),
            inet:setopts(Socket, [{active, once}]), 
            {noreply, St#st_tcprx{data=Rest}}
    end;
handle_info({tcp_closed, Socket}, #st_tcprx{socket=Socket, log=Log}=St) ->
    smpp34_log:error(Log, "tcprx: Socket closed by peer"),
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info({tcp_error, Socket, Reason}, #st_tcprx{socket=Socket, log=Log}=St) ->
    smpp34_log:error(Log, "tcprx: TCP error - ~w", [Reason]),
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info(#'DOWN'{ref=Mref, reason=unbind}, #st_tcprx{mref=Mref}=St) ->
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info(#'DOWN'{ref=Mref, reason=unbind_resp}, #st_tcprx{mref=Mref}=St) ->
	{stop, normal, St#st_tcprx{send_unbind=false}};
handle_info(#'DOWN'{ref=Mref}, #st_tcprx{mref=Mref}=St) ->
	{stop, normal, St};
handle_info(timeout, #st_tcprx{socket=Socket, log=Log}=St) ->
    inet:setopts(Socket, [{active, once}]),
    smpp34_log:warn(Log, "tcprx: Attempting network receive again"),
    {noreply, St};
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
    Pdu = #pdu{sequence_number=?SNUM_MAX, body=#unbind{}},
	case smpp34pdu:pack(Pdu) of
        {error, _} ->
            % we're exiting anyways
            ok;
        {ok, Bin} ->
            catch(gen_tcp:send(S, Bin)),
            catch(gen_tcp:close(S)),
            ok
    end.

code_change(_OldVsn, St, _Extra) ->
    {noreply, St}.
