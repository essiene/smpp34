-ifndef(util).
-define(util, true).

-define(SNUM_MAX, 16#7fffffff).

-record('DOWN', {ref, type, obj, reason}).

-endif.
