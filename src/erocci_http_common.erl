%%%-------------------------------------------------------------------
%%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%%% @copyright (c) 2013-2016 Jean Parpaillon
%%% 
%%% This file is provided to you under the license described
%%% in the file LICENSE at the root of the project.
%%%
%%% You can also download the LICENSE file from the following URL:
%%% https://github.com/erocci/erocci/blob/master/LICENSE
%%% 
%%% @doc
%%%
%%% @end
%%% Created : 25 Mar 2013 by Jean Parpaillon <jean.parpaillon@free.fr>
%%%-------------------------------------------------------------------
-module(erocci_http_common).

-include("erocci_http.hrl").
-include_lib("kernel/include/inet.hrl").

%% API
-export([start/3,
		 stop/1]).


%% @doc Start an HTTP listener
%% @end
start(Ref, Protocol, Opts) ->
    {ok, _} = application:ensure_all_started(erocci_listener_http),
    Trails = trails:trails([erocci_http_handler,
			    cowboy_swagger_handler]),
    trails:store(Trails),
    Dispatch = trails:single_host_compile(Trails),
    CowboyOpts = [
		  {env, [{dispatch, Dispatch}]},
		  {compress, true}
		 ],
    Pool = application:get_env(erocci_listener_http, pool, 10),
    cowboy:Protocol(Ref, Pool, Opts, CowboyOpts).


stop(Ref) ->
    cowboy:stop_listener(Ref).
