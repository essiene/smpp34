
-module(smpp34_esme_core_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/2, start_child/3]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, temporary, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Host, Port) ->
	supervisor:start_child(?MODULE, [self(), Host, Port, undefined]).

start_child(Host, Port, Logger) ->
	supervisor:start_child(?MODULE, [self(), Host, Port, Logger]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {simple_one_for_one, 5, 10}, [?CHILD(smpp34_esme_core, worker)]} }.

