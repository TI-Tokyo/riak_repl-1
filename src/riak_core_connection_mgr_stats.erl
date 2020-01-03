%% -------------------------------------------------------------------
%%
%% Riak Core Connection Manager Statistics
%%    collect, aggregate, and provide stats for connections made by 
%%    the connection manager
%%
%% Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(riak_core_connection_mgr_stats).
-author("Chris Tilt").

-behaviour(gen_server).

%% API
-export([start_link/0,
         get_stats/0,
         get_stats_by_ip/1,
         get_stats_by_protocol/1,
         get_consolidated_stats/0,
         update/3,
         register_stats/0,
         produce_stats/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(APP, riak_conn_mgr_stats).
-define(Prefix, riak).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

register_stats() ->
    riak_core_stat_cache:register_app(?APP, {?MODULE, produce_stats, []}).

%% @spec get_stats() -> proplist()
%% @doc Return all stats from the cached value. This will refresh
%% the cache if it's been over 5 seconds since the last query.
%% When the cache needs to get the latest values, it will call our
%% `produce_stats()' function.
get_stats() ->
    {ok, Stats, _TS} = riak_core_stat_cache:get_stats(?APP),
    Stats.

get_consolidated_stats() ->
    Strings = [format_stat(Stat) || Stat <- get_stats()],
    stats_as_atoms(Strings).

%% Sort and convert {K,V} stats to atoms
stats_as_atoms(StringStats) ->
    lists:map(fun({S,V}) -> {list_to_atom(S), V} end, lists:sort(StringStats)).

format_stat({{?APP, conn_error, StatName}, [{count,N},{one,_W}]}) ->
    {"conn_error_" ++ atom_to_list(StatName), N};
format_stat({{?APP, conn_error, StatName, total}, N}) ->
    {"conn_error_" ++ atom_to_list(StatName) ++ "_total", N};
format_stat({{?APP, conn_error, StatName, Addr, total}, N}) when not is_atom(Addr) ->
    {string_of_ipaddr(Addr) ++ "_"
     ++ "conn_error_"
     ++ atom_to_list(StatName)
     ++ "_total", N};
format_stat({{?APP, conn_error, StatName, Addr, ProtocolId, total},N}) ->
    {string_of_ipaddr(Addr) ++ "_"
     ++ "conn_error_"
     ++ atom_to_list(ProtocolId) ++ "_"
     ++ atom_to_list(StatName)
     ++ "_total" , N};
format_stat({{?APP, conn_error, StatName, ProtocolId, total},N}) ->
    {atom_to_list(ProtocolId) ++ "_"
     ++ "conn_error_"
     ++ atom_to_list(StatName)
     ++ "_total", N};
format_stat({{?APP, conn_error, StatName, Addr, ProtocolId},[{count,N},{one,_W}]}) ->
    {string_of_ipaddr(Addr) ++ "_"
     ++ "conn_error_"
     ++ atom_to_list(ProtocolId) ++ "_"
     ++ atom_to_list(StatName), N};
format_stat({{?APP, conn_error, StatName, Addr},[{count,N},{one,_W}]}) when not is_atom(Addr) ->
    {string_of_ipaddr(Addr) ++ "_"
     ++ "conn_error_"
     ++ atom_to_list(StatName), N};
format_stat({{?APP, conn_error, StatName, ProtocolId},[{count,N},{one,_W}]}) ->
    {"conn_error_" ++ atom_to_list(ProtocolId) ++ "_" ++ atom_to_list(StatName), N};

format_stat({{?APP, StatName},[{count,N},{one,_W}]}) ->
    {atom_to_list(StatName), N};
format_stat({{?APP, StatName, total},N}) ->
    {atom_to_list(StatName) ++ "_total", N};
format_stat({{?APP, StatName, Addr, total},N}) when not is_atom(Addr) ->
    {string_of_ipaddr(Addr)
     ++ "_" ++ atom_to_list(StatName) ++ "_total", N};
format_stat({{?APP, StatName, Addr},[{count,N},{one,_W}]}) when not is_atom(Addr) ->
    {string_of_ipaddr(Addr) ++ "_" ++ atom_to_list(StatName),N};
format_stat({{?APP, StatName, ProtocolId, total},N}) when is_atom(ProtocolId) ->
    {atom_to_list(ProtocolId)  ++ "_" ++ atom_to_list(StatName) ++ "_total", N};
format_stat({{?APP, StatName, ProtocolId},[{count,N},{one,_W}]}) when is_atom(ProtocolId) ->
    {atom_to_list(ProtocolId)  ++ "_" ++ atom_to_list(StatName), N};
format_stat({{?APP, StatName, Addr, ProtocolId, total},N}) when is_atom(ProtocolId) ->
    {string_of_ipaddr(Addr)
     ++ "_" ++ atom_to_list(ProtocolId) 
     ++ "_" ++ atom_to_list(StatName)
     ++ "_total", N};
format_stat({{?APP, StatName, Addr, ProtocolId},[{count,N},{one,_W}]}) when is_atom(ProtocolId) ->
    {string_of_ipaddr(Addr)
     ++ "_" ++ atom_to_list(ProtocolId) 
     ++ "_" ++ atom_to_list(StatName), N};
format_stat({riak_conn_mgr_stats_stat_ts, S}) ->
    UnivTime = riak_core_format:epoch_to_datetime(S),
    {{Year, Month, Day}, {Hour, Min, Sec}} = calendar:universal_time_to_local_time(UnivTime),
    Fmt = riak_core_format:fmt("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B",
                         [Year, Month, Day, Hour, Min, Sec]),
    {"riak_conn_mgr_stats_stat_ts", Fmt};
format_stat({StateName, N}) ->
    {atom_to_list(StateName), N};
format_stat(_) ->
    [].


string_of_ipaddr({IP, Port}) when is_list(IP) ->
    lists:flatten(io_lib:format("~s:~p", [IP, Port]));
string_of_ipaddr({IP, Port}) when is_tuple(IP) ->
    lists:flatten(io_lib:format("~s:~p", [inet_parse:ntoa(IP), Port])).

%% Get stats filtered by given IP address
get_stats_by_ip({_IP, _Port}=Addr) ->
    AllStats = get_stats(),
    Stats = lists:filter(fun(S) -> predicate_by_ip(S,Addr) end, AllStats),
    stats_as_atoms([format_stat(Stat) || Stat <- Stats]).

predicate_by_ip({{_App, conn_error, _StatName, MatchAddr, total},_Value}, MatchAddr) ->
    true;
predicate_by_ip({{_App, conn_error, _StatName, MatchAddr, _ProtocolId, total},_Value}, MatchAddr) ->
    true;
predicate_by_ip({{_App, conn_error, _StatName, MatchAddr, _ProtocolId},_Value}, MatchAddr) ->
    true;
predicate_by_ip({{_App, conn_error, _StatName, MatchAddr},_Value}, MatchAddr) ->
    true;
predicate_by_ip({{_App, conn_error, _StatName, _ProtocolId},_Value}, _MatchAddr) ->
    false;
predicate_by_ip({{_App, conn_error, _StatName, _ProtocolId, total},_Value}, _MatchAddr) ->
    false;
predicate_by_ip({{_App, _StatName, MatchAddr},_Value}, MatchAddr) ->
    true;
predicate_by_ip({{_App, _StatName, MatchAddr, total},_Value}, MatchAddr) ->
    true;
predicate_by_ip({{_App, _StatName, MatchAddr, _ProtocolId},_Value}, MatchAddr) ->
    true;
predicate_by_ip({{_App, _StatName, MatchAddr, _ProtocolId, total},_Value}, MatchAddr) ->
    true;
predicate_by_ip(_X, _MatchAddr) ->
    false.

%% Get stats filtered by given protocol-id (e.g. rt_repl)
get_stats_by_protocol(ProtocolId) ->
    AllStats = get_stats(),
    Stats = lists:filter(fun(S) -> predicate_by_protocol(S,ProtocolId) end, AllStats),
    stats_as_atoms([format_stat(Stat) || Stat <- Stats]).
    
predicate_by_protocol({{_App, conn_error, _StatName, _Addr, MatchId},_Value}, MatchId) ->
    true;
predicate_by_protocol({{_App, conn_error, _StatName, _Addr, MatchId, total},_Value}, MatchId) ->
    true;
predicate_by_protocol({{_App, conn_error, _StatName, MatchId},_Value}, MatchId) ->
    true;
predicate_by_protocol({{_App, conn_error, _StatName, MatchId, total},_Value}, MatchId) ->
    true;
predicate_by_protocol({{_App, conn_error, _StatName, _Addr},_Value}, _MatchId) ->
    false;
predicate_by_protocol({{_App, conn_error, _StatName, _Addr, total},_Value}, _MatchId) ->
    false;
predicate_by_protocol({{_App, _StatName, MatchId},_Value}, MatchId) ->
    true;
predicate_by_protocol({{_App, _StatName, MatchId, total},_Value}, MatchId) ->
    true;
predicate_by_protocol({{_App, _StatName, _Addr, MatchId},_Value}, MatchId) ->
    true;
predicate_by_protocol({{_App, _StatName, _Addr, MatchId, total},_Value}, MatchId) ->
    true;
predicate_by_protocol(_X, _MatchId) ->
    false.

%% Public interface to accumulate stats
update(Stat, Addr, ProtocolId) ->
    gen_server:cast(?SERVER, {update, Stat, Addr, ProtocolId}).

%% gen_server

init([]) ->
    register_stats(),
    {ok, ok}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast({update, Stat, Addr, ProtocolId}, State) ->
    do_update(Stat, Addr, ProtocolId),
    {noreply, State};
handle_cast(_Req, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Update a stat for given IP-Address, Cluster, and Protocol-id
do_update({conn_error, Error}, IPAddr, Protocol) ->
    create_or_update({?APP, conn_error, Error, total}, 1, counter),
    create_or_update({?APP, conn_error, Error}, 1, spiral),
    create_or_update({?APP, conn_error, Error, IPAddr, total}, 1, counter),
    create_or_update({?APP, conn_error, Error, IPAddr}, 1, spiral),
    create_or_update({?APP, conn_error, Error, Protocol, total}, 1, counter),
    create_or_update({?APP, conn_error, Error, Protocol}, 1, spiral),
    create_or_update({?APP, conn_error, Error, IPAddr, Protocol, total}, 1, counter),
    create_or_update({?APP, conn_error, Error, IPAddr, Protocol}, 1, spiral);

do_update(Stat, IPAddr, Protocol) ->
    create_or_update({?APP, Stat, total}, 1, counter),
    create_or_update({?APP, Stat}, 1, spiral),
    create_or_update({?APP, Stat, Protocol, total}, 1, counter),
    create_or_update({?APP, Stat, Protocol}, 1, spiral),
    create_or_update({?APP, Stat, IPAddr, total}, 1, counter),
    create_or_update({?APP, Stat, IPAddr }, 1, spiral),
    create_or_update({?APP, Stat, IPAddr, Protocol, total}, 1, counter),
    create_or_update({?APP, Stat, IPAddr, Protocol}, 1, spiral).

%% private

create_or_update(Name, UpdateVal, Type) ->
    ListName = tuple_to_list(Name),
    StatName = [?Prefix | ListName],
    riak_stat:update(StatName, UpdateVal, Type).

%% @spec produce_stats() -> proplist()
%% @doc Produce a proplist-formatted view of the current aggregation
%%      of stats.
produce_stats() ->
    {Stats,_} = riak_stat:get_stats(?APP),
    lists:flatten([{Stat, get_stat_value(Stat)} || Stat <- Stats]).

%% Get the value of the named stats metric
%% NOTE: won't work for Histograms
get_stat_value(Name) ->
    riak_stat_exom:get_values(Name).
