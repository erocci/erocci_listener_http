%%%-------------------------------------------------------------------
%%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%%% @copyright (c) 2014-2016 Jean Parpaillon
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
%%% Created : 18 Mar 2014 by Jean Parpaillon <jean.parpaillon@free.fr>
%%%-------------------------------------------------------------------
-module(erocci_https).

-behaviour(erocci_listener).

-include_lib("erocci_core/include/erocci_log.hrl").

%% occi_listener callbacks
-export([start_link/2,
         terminate/2]).

start_link(Ref, Opts) ->
    ?info("Starting HTTPS listener~n", []),
    erocci_http_common:start(Ref, start_https, validate_cfg(Opts)).

terminate(Ref, _Reason) ->
    erocci_http_common:stop(Ref).

%%%
%%% Priv
%%%
validate_cfg(Opts) ->
    Address = proplists:get_value(ip, Opts, {0,0,0,0}),
    Port = proplists:get_value(port, Opts, 8443),
    case proplists:is_defined(cacertfile, Opts) of
        true -> ok;
        false -> throw({missing_opt, cacertfile}) 
    end,
    case proplists:is_defined(certfile, Opts) of
        true -> ok;
        false -> throw({missing_opt, certfile}) 
    end,
    case proplists:is_defined(keyfile, Opts) of
        true -> ok;
        false -> throw({missing_opt, keyfile}) 
    end,
    [{ip, Address}, {port, Port}, {scheme, https} | Opts].
