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
-module(erocci_http).

-behaviour(occi_listener).

-include_lib("erocci_core/include/occi_log.hrl").

%% occi_listener callbacks
-export([start_link/2,
	 terminate/2]).

start_link(Ref, Opts) ->
    ?info("Starting HTTP listener~n", []),
    erocci_http_common:start(Ref, start_http, validate_cfg(Opts)).

terminate(Ref, _Reason) ->
    erocci_http_common:stop(Ref).

%%%
%%% Priv
%%%
validate_cfg(Opts) ->
    Address = proplists:get_value(ip, Opts, {0,0,0,0}),
    Port = proplists:get_value(port, Opts, 8080),
    [{ip, Address}, {port, Port}, {scheme, http} | Opts].
