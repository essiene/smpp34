-module(smpp34_log).

-export([start_link/0, stop/1, add_logger/3]).
-export([debug/2,info/2,error/2,warn/2]).
-export([debug/3,info/3,error/3,warn/3]).



start_link() ->
    gen_event:start_link().

stop(Ref) ->
    gen_event:stop(Ref).

add_logger(Ref, Logger, Args) ->
    case gen_event:add_sup_handler(Ref, Logger, Args) of
        ok ->
            ok;
        {'EXIT', Reason} ->
            {error, Reason};
        {error, Reason} ->
            {error, Reason};
        Other ->
            {error, {add_logger_bad_reply, Other}}
    end.

info(Ref, Format) ->
    info(Ref, Format, []).

info(Ref, Format, Args) ->
    log(Ref, 'INFO', Format, Args).

debug(Ref, Format) ->
    debug(Ref, Format, []).

debug(Ref, Format, Args) ->
    log(Ref, 'DEBUG', Format, Args).

warn(Ref, Format) ->
    warn(Ref, Format, []).

warn(Ref, Format, Args) ->
    log(Ref, 'WARN', Format, Args).

error(Ref, Format) ->
    error(Ref, Format, []).

error(Ref, Format, Args) ->
    log(Ref, 'ERROR', Format, Args).

log(Ref, Level, S, []) ->
    gen_event:notify(Ref, {Level, S});
log(Ref, Level, Format, FormatArgs) ->
    S = io_lib:format(Format, FormatArgs),
    gen_event:notify(Ref, {Level, S}).
