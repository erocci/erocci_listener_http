%% @author Jean Parpaillon <jean.parpaillon@free.fr>
%% @copyright (c) 2013-2016 Jean Parpaillon
%% 
%% This file is provided to you under the license described
%% in the file LICENSE at the root of the project.
%%
%% You can also download the LICENSE file from the following URL:
%% https://github.com/erocci/erocci/blob/master/LICENSE
%% 
%% @doc Handler REST requests for erocci
%% @end

-module(erocci_http_handler).

-include_lib("erocci_core/include/erocci.hrl").
-include_lib("erocci_core/include/erocci_log.hrl").
-include("erocci_http.hrl").

%% REST Callbacks
-export([init/2, 
         allowed_methods/2,
	 generate_etag/2,
         is_authorized/2,
         resource_exists/2,
         is_conflict/2,
	 malformed_request/2,
         delete_resource/2,
         content_types_provided/2,
         content_types_accepted/2]).


%% trails
-behaviour(trails_handler).
-export([trails/0]).


%% Callback callbacks
-export([to/2, from/2]).


init(Req, _Opts) -> 
    Creds = credentials(Req),
    Filter = parse_filters(cowboy_req:parse_qs(Req)),
    Req2 = cowboy_req:set_resp_header(<<"server">>, ?SERVER_ID, Req),
    case cowboy_req:path(Req2) of
	<<"/-/">> ->
	    init_capabilities(Creds, Filter , Req2);
	<<"/.well-known/org/ogf/occi/-/">> ->
	    init_capabilities(Creds, Filter, Req2);
	Path ->
	    Collections = erocci_store:collections(),
	    Path2 = occi_utils:normalize(Path),
	    case maps:is_key(Path2, Collections) of
		true ->
		    init_bounded_collection(maps:get(Path2, Collections), Creds, Filter, Req);
		false ->
		    init_node(Path2, Creds, Filter, Req2)
	    end
    end.


-define(ALL_METHODS, [<<"GET">>, <<"DELETE">>, <<"OPTIONS">>, <<"POST">>, <<"PUT">>, <<"HEAD">>]).
allowed_methods(Req, {error, method_not_allowed}=S) ->
    {[], Req, S};

allowed_methods(Req, S) ->
    {?ALL_METHODS, Req, S}.


generate_etag(Req, {error, _}=S) ->
    {undefined, Req, S};

generate_etag(Req, {ok, _, Serial}=S) ->
    {Serial, Req, S}.


-define(entity_content_type(M), [{{<<"text">>,            <<"plain">>,     []}, M},
				 {{<<"text">>,            <<"occi">>,      []}, M},
				 {{<<"application">>,     <<"json">>,      []}, M},
				 {{<<"application">>,     <<"occi+json">>, []}, M},
				 {{<<"application">>,     <<"xml">>,       []}, M},
				 {{<<"application">>,     <<"occi+xml">>,  []}, M}]).
-define(content_type(M), ?entity_content_type(M) ++ [ {{<<"text">>,    <<"uri-list">>,  []}, M} ]).

content_types_provided(Req, {ok, Obj, _Serial}=S) ->
    case occi_type:type(Obj) of
	categories -> {?content_type(to), Req, S};
	collection -> {?content_type(to), Req, S};
	_ ->          {?entity_content_type(to), Req, S}
    end;

content_types_provided(Req, S) ->
    {?content_type(to), Req, S}.


content_types_accepted(Req, S) ->
    {?content_type(from), Req, S}.


resource_exists(Req, {error, not_found}=S) ->
    {false, Req, S};

resource_exists(Req, S) ->
    {true, Req, S}.


is_authorized(Req, {error, {unauthorized, Challenge}}=S) ->
    {{false, Challenge}, Req, S};

is_authorized(Req, S) ->
    {true, Req, S}.


is_conflict(Req, {error, conflict}=S) ->
    {true, Req, S};

is_conflict(Req, S) ->
    {false, Req, S}.


malformed_request(Req, {error, {parse_error, _}=Err}=S) ->
    {true, errors(Err, Req), S};

malformed_request(Req, S) ->
    {false, Req, S}.


delete_resource(Req, ok) ->
    {true, Req, ok};

delete_resource(Req, {error, Err}=S) ->
    {false, errors(Err, Req), S}.


to(Req, {error, Err}=S) ->
    ?error("HTTP listener error: ~p~n", [Err]),
    {halt, errors(Err, Req), S};

to(Req, {ok, Obj, _Serial}) ->
    Mimetype = cowboy_req:header(<<"accept">>, Req),
    Ctx = occi_uri:from_string(cowboy_req:url(Req)),
    Body = occi_rendering:render(Mimetype, Obj, Ctx),
    {[Body, "\n"], Req, {ok, Obj}}.


from(Req, {ok, Obj, _Serial}=S) ->
    Mimetype = cowboy_req:header(<<"accept">>, Req),
    Body = occi_rendering:render(Mimetype, Obj),
    {true, cowboy_req:set_resp_body([Body, "\n"], Req), S};

from(Req, {error, Err}=S) ->
    {false, errors(Err, Req), S}.


%% @doc Return trail definitions
%% @end
-define(trails_mimetypes, [<<"text/plain">>, <<"text/occi">>, <<"application/occi+json">>, 
			   <<"application/json">>, <<"applicaton/occi+xml">>, <<"applicaton/xml">>]).
trails() ->
    Query = trails:trail(<<"/-/">>, ?MODULE, [],
			 #{get =>
			       #{ tags => [<<"Query Interface">>],
				  description => <<"Retrieve Category instances">>,
				  consumes => [],
				  produces => [ <<"text/uri-list">> | ?trails_mimetypes ]
				},
			   post =>
			       #{ tags => [<<"Query Interface">>],
				  description => <<"Add a user-defined Mixin instance">>,
				  consumes => ?trails_mimetypes,
				  produces => []},
			   delete =>
			       #{ tags => [<<"Query Interface">>],
				  description => <<"Remove a user-defined Mixin instance">>,
				  consumes => ?trails_mimetypes,
				  produces => []}
			  }),
    maps:fold(fun (Location, Category, Acc) ->
		  category_metadata(occi_category:class(Category), Location, Category, Acc)
	      end, [ Query ], erocci_store:collections()).

%% @doc Return trail definitions
%% @end
-define(trails_mimetypes, ["text/plain", "text/occi", "application/occi+json", 
						   "application/json", "applicaton/occi+xml", "applicaton/xml"]).
trails_query(Opts) ->
    QueryShort = trails:trail(<<"/-/">>, ?MODULE, Opts,
							  #{get =>
									#{ tags => [<<"Query Interface">>],
									   description => <<"Retrieve Category instances">>,
									   consumes => [],
									   produces => [ "text/uri-list" | ?trails_mimetypes ]
									 },
								post =>
									#{ tags => [<<"Query Interface">>],
									   description => <<"Add a user-defined Mixin instance">>,
									   consumes => ?trails_mimetypes,
									   produces => []},
								delete =>
									#{ tags => [<<"Query Interface">>],
									   description => <<"Remove a user-defined Mixin instance">>,
									   consumes => ?trails_mimetypes,
									   produces => []}
							   }),
	QueryNorm = trails:trail(<<"/.well-known/org/ogf/occi/-">>, ?MODULE, Opts, #{}),
	[ QueryShort, QueryNorm ].


trails_collections(Opts) ->
	{ Kinds, Mixins, _ } = occi_category_mgr:find_all(),
	Trails = lists:foldl(fun (Kind, Acc) ->
	 							 [ kind_metadata(Kind, Opts) | Acc ]
						 end, [], Kinds),
	lists:reverse(lists:foldl(fun (Mixin, Acc) ->
									  [ mixin_metadata(Mixin, Opts) | Acc ]
							  end, Trails, Mixins)).

trails_all(Opts) ->
	[ trails:trail('_', ?MODULE, Opts, #{}) ].

%%%
%%% Private
%%%
init_capabilities(Creds, Filter, Req) ->
    S = case cowboy_req:method(Req) of
	    <<"GET">> ->
		erocci_store:capabilities(Creds, Filter);
	    <<"DELETE">> ->
		parse(Req, fun (Obj) -> erocci_store:delete_mixin(Obj, Creds) end);
	    <<"POST">> ->
		parse(Req, fun(Obj) -> erocci_store:new_mixin(Obj, Creds) end);
	    <<"OPTIONS">> ->
		erocci_store:capabilities(Creds, Filter, cowboy_req:url(Req));
	    <<"HEAD">> ->
		erocci_store:capabilities(Creds, Filter, cowboy_req:url(Req));
	    _ ->
		{error, method_not_allowed}
	end,
    {cowboy_rest, cors(<<"GET, DELETE, POST, OPTIONS, HEAD">>, Req), S}.


init_bounded_collection(Category, Creds, Filter, Req) ->
    S = case {occi_category:class(Category), cowboy_req:method(Req)} of
	    {_, <<"GET">>} ->
		case parse_range(Req) of
		    {ok, Start, Number} ->
			erocci_store:collection(Category, Creds, Filter, Start, Number);
		    {error, _}=Err ->
			Err
		end;
	    {kind, <<"DELETE">>} ->
		erocci_store:delete_all(Category, Creds);
	    {mixin, <<"DELETE">>} ->
		parse(Req, fun (Obj) -> erocci_store:remove_mixin(Category, Obj, Creds) end);
	    {kind, <<"POST">>} ->
		case cowboy_req:match_qs([action], Req) of
		    #{ action := Action } ->
			parse(Req, fun (Obj) -> 
					   erocci_store:action(Category, Action, Obj, Creds) 
				   end);
		    _ ->
			parse(Req, fun (Obj) -> 
					   erocci_store:create(Category, Obj, Creds)
				   end)
		end;
	    {mixin, <<"POST">>} ->
		case cowboy_req:match_qs([action], Req) of
		    #{ action := Action } ->
			parse(Req, fun (Obj) -> 
					   erocci_store:action(Category, Action, Obj, Creds) 
				   end);
		    _ ->
			parse(Req, fun (Obj) -> 
					   erocci_store:append_mixin(Category, Obj, Creds)
				   end)
		end;
	    {mixin, <<"PUT">>} ->
		parse(Req, fun(Obj) -> erocci_store:set_mixin(Category, Obj, Creds) end);
	    {_, <<"OPTIONS">>} ->
		erocci_store:collection(Category, Creds, Filter, 0, 0);
	    {_, <<"HEAD">>} ->
		erocci_store:collection(Category, Creds, Filter, 0, 0);
	    _ ->
		{error, method_not_allowed}
	end,
    Allows = case occi_category:class(Category) of
		 kind -> <<"GET, DELETE, POST, OPTIONS, HEAD">>;
		 mixin -> <<"GET, DELETE, POST, PUT, OPTIONS, HEAD">>
	     end,
    {cowboy_rest, cors(Allows, Req), S}.


init_node(Path, Creds, Filter, Req) ->
    S = case cowboy_req:method(Req) of
	    <<"GET">> ->
		case parse_range(Req) of
		    {ok, Start, Number} ->
			erocci_store:get(Path, Creds, Filter, Start, Number);
		    {error, _}=Err ->
			Err
		end;
	    <<"DELETE">> ->
		erocci_store:delete(Path, Creds);
	    <<"POST">> ->
		case cowboy_req:match_qs([action], Req) of
		    #{ action := Action } ->
			parse(Req, fun (Obj) -> 
					   erocci_store:action(Path, Action, Obj, Creds) 
				   end);
		    _ ->
			parse(Req, fun (Obj) -> 
					   erocci_store:update(Path, Obj, Creds) 
				   end)
		end;
	    <<"PUT">> ->
		parse(Req, fun (Obj) -> erocci_store:create(Path, Obj, Creds) end);
	    <<"OPTIONS">> ->
		erocci_store:get(Path, Creds, Filter);
	    <<"HEAD">> ->
		erocci_store:get(Path, Creds, Filter);
	    _ ->
		{error, method_not_allowed}
	end,
    {cowboy_rest, cors(<<"GET, DELETE, POST, PUT, OPTIONS, HEAD">>, Req), S}.


parse(Req, Next) ->
    Next({cowboy_req:header(<<"content-type">>, Req), cowboy_req:body(Req)}).


credentials(Req) ->
    Challenge = fun (_Creds) ->
			application:get_env(erocci_listener_http, realm, <<"erocci">>)
		end,
    case cowboy_req:parse_header(<<"authorization">>, Req) of
	{<<"basic">>, {User, Password}} ->
	    erocci_creds:basic(User, Password, Challenge);
	_ ->
	    erocci_creds:basic(Challenge)
    end.


errors(Err, Req) ->
    Body = erocci_errors:render(cowboy_req:header(<<"accept">>, Req), Err),
    cowboy_req:set_resp_body(Body, Req).


parse_filters(Qs) ->
    case parse_filters(Qs, []) of
	[] ->
	    [];
	Filters ->
	    lists:foldl(fun ({'=:=', Name, Val}, Acc) ->
				erocci_filter:add_eq(Name, Val, Acc);
			    ({like, '_', Val}, Acc) ->
				erocci_filter:add_like('_', Val, Acc)
			end, erocci_filter:new(), Filters)
    end.


parse_filters([], Acc) ->
    lists:reverse(Acc);

parse_filters([ {<<"category">>, Bin} | Tail ], Acc) ->
    case parse_category_filter(Bin) of
	undefined ->
	    parse_filters(Tail, Acc);
	Category ->
	    parse_filters(Tail, [Category | Acc])
    end;

parse_filters([ {<<"q">>, Bin} | Tail ], Acc) ->
    Acc2 = parse_attr_filters(binary:split(Bin, <<"+">>), Acc),
    parse_filters(Tail, Acc2);

parse_filters([ _ | Tail ], Acc) ->
    parse_filters(Tail, Acc).


parse_category_filter(Bin) ->
    case binary:split(uri:unquote(Bin), [<<$#>>], [trim_all]) of
        [Scheme, Term] -> [{'=:=', scheme, Scheme}, {'=:=', term, Term}];
	[Scheme] -> [{'=:=', scheme, Scheme}];
        _ -> []
    end.


parse_attr_filters([], Acc) ->
    Acc;

parse_attr_filters([ Attr | Tail ], Acc) ->
    case binary:split(uri:unquote(Attr), <<"=">>) of
        [] -> 
	    parse_attr_filters(Tail, Acc);
        [Val] -> 
	    parse_attr_filters(Tail, [{like, '_', Val} | Acc]);
        [Name, Val] -> 
	    parse_attr_filters(Tail, [ {'=:=', Name, Val} | Acc ])
    end.


parse_range(Req) ->
    try cowboy_req:match_qs([{page, int, 0}, {number, int, 0}], Req) of
	#{ page := Page, number := Number } ->
	    {ok, (Page-1) * Number, Number}
    catch error:{case_clause, _} ->
	    {error, {parse_error, range}}
    end.


category_metadata(kind, Location, C, Acc) ->
    {Scheme, Term} = occi_category:id(C),
    Name = iolist_to_binary(io_lib:format("~s~s", [Scheme, Term])),
    Title = occi_category:title(C),
    Map = #{ get => 
		 #{ tags => [Name],
		    description => 
			iolist_to_binary(
			  io_lib:format("Retrieve the collection of entities of the kind ~s (~s)",
					[Name, Title])),
		    consumes => [],
		    produces => [ <<"text/uri-list">> | ?trails_mimetypes ]},
	     post => 
		 #{ tags => [Name],
		    description => 
			iolist_to_binary(
			  io_lib:format("Creates a new entity the kind ~s (~s)",
					[Name, Title])),
		    consumes => ?trails_mimetypes,
		    produces => ?trails_mimetypes},
	     delete => 
		 #{ tags => [Name],
		    description =>
			iolist_to_binary(
			  io_lib:format("Remove entities of the kind ~s (~s)", [Name, Title])),
		    consumes => [],
		    produces => []}},
    [ trails:trail(Location, ?MODULE, [], Map) | Acc ];

category_metadata(mixin, Location, C, Acc) ->
    {Scheme, Term} = occi_category:id(C),
    Name = iolist_to_binary(io_lib:format("~s~s", [Scheme, Term])),
    Title = occi_category:title(C),
    Map = #{ get => 
		 #{ tags => [Name],
		    description => 
			iolist_to_binary(
			  io_lib:format("Retrieve the collection of entities associated with mixin ~s (~s)",
					[Name, Title])),
		    consumes => [],
		    produces => [ <<"text/uri-list">> | ?trails_mimetypes ]},
	     put => 
		 #{ tags => [Name],
		    description => 
			iolist_to_binary(
			  io_lib:format("Set the full collection of entities associated with mixin ~s (~s)",
					[Name, Title])),
		    consumes => ?trails_mimetypes,
		    produces => ?trails_mimetypes},
	     post => 
		 #{ tags => [Name],
		    description => 
			iolist_to_binary(
			  io_lib:format("Add entities to the collection of entities associated with mixin ~s (~s)",
					[Name, Title])),
		    consumes => ?trails_mimetypes,
		    produces => ?trails_mimetypes},
	     delete => 
		 #{ tags => [Name],
		    description =>
			iolist_to_binary(
			  io_lib:format("Remove entities from the mixin collection ~s (~s)", 
					[Name, Title])),
		    consumes => [],
		    produces => []}},
    [ trails:trail(Location, ?MODULE, [], Map) | Acc ].


-define(EXPOSE_HEADERS, <<"server,category,link,x-occi-attribute,x-occi-location,location">>).
cors(Methods, Req) ->
    case cowboy_req:header(<<"origin">>, Req) of
	undefined -> 
	    Req;
	Origin ->
	    Req1 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>, Methods, Req),
	    Req2 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, Origin, Req1),
	    cowboy_req:set_resp_header(<<"access-control-expose-headers">>, ?EXPOSE_HEADERS, Req2)
    end.
