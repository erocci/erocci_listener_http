%%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%%% @copyright (C) 2016, Jean Parpaillon
%%% @doc
%%%
%%% @end
%%% Created : 27 Jun 2016 by Jean Parpaillon <jean.parpaillon@free.fr>

-module(erocci_http_cors).

-include_lib("erocci_core/include/erocci_log.hrl").

-behaviour(cowboy_middleware).

-define(EXPOSE_HEADERS, <<"server,category,link,x-occi-attribute,x-occi-location,location">>).
-define(ALLOWED_METHODS, <<"GET,DELETE,PUT,POST">>).

-export([execute/2]).

%% @private
execute(Req, Env) ->
    case cowboy_req:header(<<"origin">>, Req) of
        undefined->
            {ok, Req, Env};
        OriginHeader ->
			case cow_http_hd:parse_origin(OriginHeader) of
				[] ->
					{ok, Req, Env};
				[ Origin | _ ] ->
					{_, AllowedOrigin} = lists:keyfind(allowed_origin, 1, Env),
					case match_origin(Origin, AllowedOrigin) of
						true ->
							Req1 = handle_cors(OriginHeader, Req),
							{ok, Req1, Env};
						false ->
							{ok, Req, Env}
					end
			end
    end.


handle_cors(Origin, Req) ->
	Req2 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, Origin, Req),
	Req3 = cowboy_req:set_resp_header(<<"vary">>, <<"origin">>, Req2),
	case cowboy_req:method(Req) of
		<<"OPTIONS">> ->
			Req4 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>, ?ALLOWED_METHODS, Req3),
			Req5 = cowboy_req:set_resp_header(<<"access-control-allow-headers">>, ?EXPOSE_HEADERS, Req4),
			Req6 = cowboy_req:set_resp_header(<<"access-control-max-age">>, <<"0">>, Req5),
			Req6;
		_ ->
			Req3
	end.

	
match_origin(Val, '*') when is_reference(Val) -> true;
match_origin(_, '*') -> true;
match_origin(Val, Val) -> true;
match_origin(Val, L) when is_list(L) -> lists:member(Val, L);
match_origin(_, _) -> false.
