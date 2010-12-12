-module(smpp34_log).

-export([start_link/0, stop/1, add_logger/3]).
-export([debug/2,info/2,error/2,warn/2]).



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
            {error, Reason}
        Other ->
            {error, {add_logger_bad_reply, Other}}
    end.

debug(Ref, Term) ->
    log(Ref, debug, Term).

info(Ref, Term) ->
    log(Ref, info, Term).

error(Ref, Term) ->
    log(Ref, error, Term).

warn(Ref, Term) ->
    log(Ref, warn, Term).

log(Ref, Tag, Term) ->
    gen_event:notify(Ref, {Tag, Term}).
