-module(dkq).

-export([new/0, new/1, in/2, out/1, len/1, item/2]).


-record(dkq, {q, delta=100}).
-record(item, {tstmp, tmout, d}).

new() ->
	#dkq{q=queue:new()}.

new(Delta) ->
	#dkq{q=queue:new(), delta=Delta}.

in(#item{}=Item, #dkq{q=Q0}) ->
	Q1 = queue:in(Item, Q0),
	#dkq{q=Q1}.

out(#dkq{q=Q0, delta=Delta}=Dkq0) ->
	T2 = now(),
	case queue:out(Q0) of
		{empty, Q0} ->
			{empty, Dkq0};
		{{value, #item{tmout=infinity, d=Data}}, Q1} ->
			Dkq1 = Dkq0#dkq{q=Q1},
			{{value, Data}, Dkq1};
		{{value, #item{tstmp=T1, tmout=Timeout, d=Data}}, Q1} ->
			% now_diff results are in micros secs, 
			% while Timeout is in milliseconds
			case timer:now_diff(T2, T1)/1000 of
				% Should be less than a 100ms before Timeout occurs
				% else race condition can occur where we send reply,
				% but before we actually send it, damn call timesout.
				% maybe 100ms is too much, but we'll start with this
				N when N < Timeout - Delta ->
					Dkq1 = Dkq0#dkq{q=Q1},
					{{value, Data}, Dkq1};
				_ ->
					Dkq1 = Dkq0#dkq{q=Q1},
					{{decayed, Data}, Dkq1}
			end
	end.

len(Q) ->
	queue:len(Q).


item(Timeout, Data) ->
	#item{tstmp=now(), tmout=Timeout, d=Data}.
