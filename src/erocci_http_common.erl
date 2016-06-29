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

% API
-export([start/1,
		 stop/1]).


%% @doc Start an HTTP listener
%% @end
start(StartFun) ->
    {ok, _} = application:ensure_all_started(erocci_listener_http),
	Trails0 = case application:get_env(erocci_listener_http, frontend, false) of
				  true ->
					  Dir = erocci_http_frontend:dir(),
					  [
					   {<<"/">>, erocci_http_frontend, []},
					   {<<"/_frontend/">>, cowboy_static, {file, filename:join([Dir, "index.html"])}},
					   {<<"/_frontend/[...]">>, cowboy_static, 
						{dir, Dir, [{mimetypes, cow_mimetypes, all}]}
					   }
					  ];
				  false ->
					  []
			  end,
    Trails = Trails0
		++ cowboy_swagger_handler:trails()
		++ erocci_http_handler:trails_query()
		++ erocci_http_handler:trails_collections()
		++ erocci_http_handler:trails_all(),
    trails:store(Trails),
    Dispatch = trails:single_host_compile(Trails),
	%% Middlewares = case application:get_env(erocci_listener_http, frontend, false) of
	%% 				  true ->
	%% 					  [ erocci_http_frontend, cowboy_router, erocci_http_cors, cowboy_handler ];
	%% 				  false ->
	%% 					  [ cowboy_router, erocci_http_cors, cowboy_handler ]
	%% 			  end,
    CowboyOpts = [
				  {env, [
						 {dispatch, Dispatch},
						 {allowed_origin, application:get_env(erocci_listener_http, allowed_origin, undefined)}
						]},
				  {compress, true},
				  {middlewares, [ cowboy_router, erocci_http_cors, cowboy_handler ]}
		 ],
    Pool = application:get_env(erocci_listener_http, pool, 10),
    StartFun(Pool, CowboyOpts).


stop(Ref) ->
    cowboy:stop_listener(Ref).


%%%
%%% Priv
%%%
