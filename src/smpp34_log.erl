-module(smpp34_log).

-export([debug/2,info/2,error/2,warn/2]).



debug(Pid, Term) ->
    log(Pid, esme_log_debug, Term).

info(Pid, Term) ->
    log(Pid, esme_log_info, Term).

error(Pid, Term) ->
    log(Pid, esme_log_error, Term).

warn(Pid, Term) ->
    log(Pid, esme_log_warn, Term).

log(Pid, Tag, Term) when is_pid(Pid) ->
    Pid ! {Tag, self(), Term};
log(_,_,_) ->
    ok;

