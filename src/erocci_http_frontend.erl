%%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%%% @copyright (C) 2016, Jean Parpaillon
%%% @doc
%%%
%%% @end
%%% Created : 29 Jun 2016 by Jean Parpaillon <jean.parpaillon@free.fr>

-module(erocci_http_frontend).

-include_lib("erocci_core/include/erocci_log.hrl").

-export([init/2]).


init(Req, []) ->
	Redirect = <<"/_frontend/">>,
	Req2 = cowboy_req:reply(301, [{<<"location">>, Redirect}], Req),
	{ok, Req2, nostate}.

