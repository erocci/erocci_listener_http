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
		 stop/1,
		 set_cors/2]).


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


%% Convenience function for setting CORS headers
-define(EXPOSE_HEADERS, <<"server,category,link,x-occi-attribute,x-occi-location,location">>).
set_cors(Req, Methods) ->
    case cowboy_req:header(<<"origin">>, Req) of
		{undefined, Req1} -> 
			Req1;
		{Origin, Req1} ->
			Req2 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>, Methods, Req1),
			Req3 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, Origin, Req2),
			cowboy_req:set_resp_header(<<"access-control-expose-headers">>, ?EXPOSE_HEADERS, Req3)
    end.
