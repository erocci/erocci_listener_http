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
-include_lib("erocci_core/include/erocci_log.hrl").
-include_lib("kernel/include/inet.hrl").

% API
-export([start/1,
		 stop/1]).


%% @doc Start an HTTP listener
%% @end
start(StartFun) ->
    {ok, _} = application:ensure_all_started(erocci_listener_http),
	{Frontend, Trails0} = case application:get_env(erocci_listener_http, frontend, undefined) of
							  undefined ->
								  {false, []};
							  FrontendPath when is_list(FrontendPath) ->
								  {true, frontend_routes(FrontendPath)};
							  FrontendPath when is_binary(FrontendPath)-> 
								  {true, frontend_routes(binary_to_list(FrontendPath))};
							  Else ->
								  throw({invalid_config, {frontend, Else}})
						  end,
	HandlerOpts = #{ frontend => Frontend },
    Trails = Trails0
		++ cowboy_swagger_handler:trails()
		++ erocci_http_handler:trails_query(HandlerOpts)
		++ erocci_http_handler:trails_collections(HandlerOpts)
		++ erocci_http_handler:trails_all(HandlerOpts),
    trails:store(Trails),
    Dispatch = trails:single_host_compile(Trails),
    CowboyOpts = [
				  {env, [
						 {dispatch, Dispatch},
						 {allowed_origin, application:get_env(erocci_listener_http, allowed_origin, undefined)}
						]},
				  {compress, true},
				  {middlewares, [cowboy_router, erocci_http_cors, cowboy_handler]}
		 ],
    Pool = application:get_env(erocci_listener_http, pool, 10),
    StartFun(Pool, CowboyOpts).


stop(Ref) ->
    cowboy:stop_listener(Ref).


%%%
%%% Priv
%%%
frontend_routes(FrontendPath) ->
	case where_is(FrontendPath) of
		non_existing -> 
			[];
		Dir ->
			[
			 {<<"/">>, erocci_http_frontend, []},
			 {<<"/_frontend/">>, cowboy_static, {file, filename:join([Dir, "index.html"])}},
			 {<<"/_frontend/[...]">>, cowboy_static, 
			  {dir, Dir, [{mimetypes, cow_mimetypes, all}]}
			 }
			]
	end.


where_is(<< $/, _ >> = AbsPath) ->
	AbsPath;

where_is(Path) ->
	where_is(Path, code:get_path()).

where_is(_, []) ->
	non_existing;

where_is(Path, [ CodePath | Tail ]) ->
	case filelib:wildcard(Path, CodePath) of
		[Path] -> filename:join(CodePath, Path);
		_ -> where_is(Path, Tail)
	end.
