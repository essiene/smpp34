-module(smpp34_snum_tests).
-include_lib("eunit/include/eunit.hrl").


snum_test_() ->
    {ok, Snum0} = smpp34_snum:start_link(self()),
	{ok, Snum1} = smpp34_snum:start_link(self(), 56),
	{ok, Snum2} = smpp34_snum:start_link(self(), 16#7fffffff),


    [
		{"First call to Snum0 will yield 1", 
			?_assertEqual({ok, 1}, smpp34_snum:next(Snum0))},
		{"First call to Snum1 will yield 57", 
			?_assertEqual({ok, 57}, smpp34_snum:next(Snum1))},
		{"Second call to Snum0 will yield 2", 
			?_assertEqual({ok, 2}, smpp34_snum:next(Snum0))},
		{"Second call to Snum1 will yield 58", 
			?_assertEqual({ok, 58}, smpp34_snum:next(Snum1))},
		{"Third call to Snum0 will 3", 
			?_assertEqual({ok, 3}, smpp34_snum:next(Snum0))},
		{"Third call to Snum1 will 59", 
			?_assertEqual({ok, 59}, smpp34_snum:next(Snum1))},
		{"A stop will succeed",
			?_assertEqual(ok, smpp34_snum:stop(Snum0))},
		{"A stop will succeed",
			?_assertEqual(ok, smpp34_snum:stop(Snum1))},
		{"Will loop when max reached",
			?_assertEqual({ok, 1}, smpp34_snum:next(Snum2))}
    ].


