%%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%%% @copyright (C) 2016, Jean Parpaillon
%%% @doc
%%%
%%% @end
%%% Created : 29 Jun 2016 by Jean Parpaillon <jean.parpaillon@free.fr>

-module(erocci_http_frontend).

-include_lib("erocci_core/include/erocci_log.hrl").

-export([init/2]).

-export([dir/0]).


init(Req, []) ->
	Redirect = <<"/_frontend/">>,
	Req2 = cowboy_req:reply(301, [{<<"location">>, Redirect}], Req),
	{ok, Req2, nostate}.
	

dir() ->
	case app_dir("erocci_frontend", code:get_path()) of
		error ->
			throw({notfound, erocci_frontend});
		Dir -> 
			filename:join([Dir, "app"])
	end.


%%%
%%% Priv
%%%
app_dir(_, []) ->
	error;

app_dir(App, [ Path | Tail ]) ->
	case filename:basename(Path) of
		App ->
			Path;
		_ ->
			case filelib:wildcard(App, Path) of
				[App] ->
					filename:join([Path, App]);
				_ ->
					app_dir(App, Tail)
			end
	end.
