-module(file_logger).
-behaviour(gen_event).

-export([init/1,handle_event/2,handle_call/2,
         handle_info/2,terminate/2,code_change/3]).

-record(st_flogger, {filename, io_device}).


init([FileName]) ->
    {ok, IoDevice} = file:open(FileName, [append]),
    {ok, #st_flogger{filename=FileName, io_device=IoDevice}}.

handle_event({'ERROR', Log}, #st_flogger{io_device=IoDev}=St) ->
    error_logger:error_msg("~s~n", [Log]),
    io:format(IoDev, "~s~n", [Log]),
    {ok, St};
handle_event({_, Log}, #st_flogger{io_device=IoDev}=St) ->
    io:format(IoDev, "~s~n", [Log]),
    {ok, St};
handle_event(_, St) ->
    {ok, St}.

handle_call(_, St) ->
    {ok, ok, St}.

handle_info(_, St) ->
    {ok, St}.

terminate(_, #st_flogger{io_device=IoDev}) ->
    io:format(IoDev, "Logger terminating~n"),
    file:close(IoDev),
    ok.

code_change(_OldVsn, St, _Extra) ->
    {ok, St}.

