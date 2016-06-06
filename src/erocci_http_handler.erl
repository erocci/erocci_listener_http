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
	 valid_entity_length/2,
         content_types_provided/2,
         content_types_accepted/2]).


%% trails
-export([trails_query/0,
	 trails_collections/0,
	 trails_all/0]).


%% Callback callbacks
-export([to/2, from/2]).


init(Req, Type) -> 
    Creds = credentials(Req),
    Filter = parse_filters(cowboy_req:parse_qs(Req)),
    Req2 = cowboy_req:set_resp_header(<<"server">>, ?SERVER_ID, Req),
    init2(Req2, Type, Creds, Filter).


-define(ALL_METHODS, [<<"GET">>, <<"DELETE">>, <<"OPTIONS">>, <<"POST">>, <<"PUT">>, <<"HEAD">>]).
allowed_methods(Req, {error, method_not_allowed}=S) ->
    {[], Req, S};

allowed_methods(Req, S) ->
    {?ALL_METHODS, Req, S}.


generate_etag(Req, {error, _}=S) ->
    {undefined, Req, S};

generate_etag(Req, {ok, _, Serial}=S) ->
    {Serial, Req, S}.


valid_entity_length(Req, {error, badlength}=S) ->
    {false, Req, S};

valid_entity_length(Req, S) ->
    {true, Req, S}.


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

malformed_request(Req, {error, {badkey, _}=Err}=S) ->
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


from(Req, {ok, Obj}=S) ->
    Mimetype = cowboy_req:header(<<"accept">>, Req),
    Ctx = occi_uri:from_string(cowboy_req:url(Req)),
    Body = occi_rendering:render(Mimetype, Obj, Ctx),
    {true, cowboy_req:set_resp_body([Body, "\n"], Req), S};

from(Req, {error, Err}=S) ->
    {false, errors(Err, Req), S}.


%% @doc Return trail definitions
%% @end
-define(trails_mimetypes, [<<"text/plain">>, <<"text/occi">>, <<"application/occi+json">>, 
			   <<"application/json">>, <<"applicaton/occi+xml">>, <<"applicaton/xml">>]).
trails_query() ->
    QueryShort = trails:trail(<<"/-/">>, ?MODULE, query,
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
    QueryNorm = trails:trail(<<"/.well-known/org/ogf/occi/-">>, ?MODULE, query, #{}),
    [ QueryShort, QueryNorm ].


trails_collections() ->
    maps:fold(fun (Location, Category, Acc) ->
		      category_metadata(occi_category:class(Category), Location, Category, Acc)
	      end, [], erocci_store:collections()).


trails_all() ->
    [ trails:trail('_', ?MODULE, undefined, #{}) ].


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
init2(Req, query, Creds, Filter) ->
    init_capabilities(Creds, Filter , Req);

init2(Req, {kind, Kind}, Creds, Filter) ->
    init_kind_collection(Kind, Creds, Filter, Req);

init2(Req, {mixin, Mixin}, Creds, Filter) ->
    init_mixin_collection(Mixin, Creds, Filter, Req);
    
init2(Req, undefined, Creds, Filter) ->
    init_node(Creds, Filter, Req).


init_capabilities(Creds, Filter, Req) ->
    {S, Req1} = case cowboy_req:method(Req) of
		    <<"GET">> ->
			{erocci_store:capabilities(Creds, Filter), Req};
		    <<"DELETE">> ->
			parse(Req, fun (Obj) -> erocci_store:delete_mixin(Obj, Creds) end);
		    <<"POST">> ->
			parse(Req, fun(Obj) -> 
					   erocci_store:new_mixin(Obj, Creds)
				   end);
		    <<"OPTIONS">> ->
			{erocci_store:capabilities(Creds, Filter, cowboy_req:url(Req)), Req};
		    <<"HEAD">> ->
			{erocci_store:capabilities(Creds, Filter, cowboy_req:url(Req)), Req};
		    _ ->
			{{error, method_not_allowed}, Req}
		end,
    {cowboy_rest, cors(<<"GET, DELETE, POST, OPTIONS, HEAD">>, Req1), S}.


init_kind_collection(Kind, Creds, Filter, Req) ->
    {S, Req1} = case cowboy_req:method(Req) of
		    <<"GET">> ->
			case parse_range(Req) of
			    {ok, Start, Number} ->
				{erocci_store:collection(Kind, Creds, Filter, Start, Number), Req};
			    {error, _}=Err ->
				{Err, Req}
			end;
		    <<"DELETE">> ->
			{erocci_store:delete_all(Kind, Creds), Req};
		    <<"POST">> ->
			try cowboy_req:match_qs([action], Req) of
			    #{ action := Action } ->
				parse(Req, fun (Obj) -> 
						   erocci_store:action(Kind, Action, Obj, Creds)
					   end)
			catch error:{badmatch, false} ->
				parse(Req, fun (Obj) -> 
						   erocci_store:create(Kind, Obj, Creds)
					   end)
			end;
		    <<"OPTIONS">> ->
			{erocci_store:collection(Kind, Creds, Filter, 0, 0), Req};
		    <<"HEAD">> ->
			{erocci_store:collection(Kind, Creds, Filter, 0, 0), Req};
		    _ ->
			{{error, method_not_allowed}, Req}
		end,
    Allows = <<"GET, DELETE, POST, OPTIONS, HEAD">>,
    {cowboy_rest, cors(Allows, Req1), S}.


init_mixin_collection(Mixin, Creds, Filter, Req) ->
    {S, Req1} = case cowboy_req:method(Req) of
		    <<"GET">> ->
			case parse_range(Req) of
			    {ok, Start, Number} ->
				{erocci_store:collection(Mixin, Creds, Filter, Start, Number), Req};
			    {error, _}=Err ->
				{Err, Req}
			end;
		    <<"DELETE">> ->
			parse(Req, fun (Obj) -> erocci_store:remove_mixin(Mixin, Obj, Creds) end);
		    <<"POST">> ->
			try cowboy_req:match_qs([action], Req) of
			    #{ action := Action } ->
				parse(Req, fun (Obj) -> 
						   erocci_store:action(Mixin, Action, Obj, Creds) 
					   end)
			catch error:{badmatch, false} ->
				parse(Req, fun (Obj) -> 
						   erocci_store:append_mixin(Mixin, Obj, Creds)
					   end)
			end;
		    <<"PUT">> ->
			parse(Req, fun(Obj) -> erocci_store:set_mixin(Mixin, Obj, Creds) end);
		    <<"OPTIONS">> ->
			{erocci_store:collection(Mixin, Creds, Filter, 0, 0), Req};
		    <<"HEAD">> ->
			{erocci_store:collection(Mixin, Creds, Filter, 0, 0), Req};
		    _ ->
			{{error, method_not_allowed}, Req}
		end,
    Allows = <<"GET, DELETE, POST, PUT, OPTIONS, HEAD">>,
    {cowboy_rest, cors(Allows, Req1), S}.


init_node(Creds, Filter, Req) ->
    Path = occi_utils:normalize(cowboy_req:path(Req)),
    {S, Req1} = case cowboy_req:method(Req) of
		    <<"GET">> ->
			case parse_range(Req) of
			    {ok, Start, Number} ->
				{erocci_store:get(Path, Creds, Filter, Start, Number), Req};
			    {error, _}=Err ->
				Err
			end;
		    <<"DELETE">> ->
			{erocci_store:delete(Path, Creds), Req};
		    <<"POST">> ->
			try cowboy_req:match_qs([action], Req) of
			    #{ action := Action } ->
				parse(Req, fun (Obj) -> 
						   erocci_store:action(Path, Action, Obj, Creds) 
					   end)
			catch error:{badmatch, false} ->
				parse(Req, fun (Obj) -> 
						   erocci_store:update(Path, Obj, Creds) 
					   end)
			end;
		    <<"PUT">> ->
			parse(Req, fun (Obj) -> erocci_store:create(Path, Obj, Creds) end);
		    <<"OPTIONS">> ->
			{erocci_store:get(Path, Creds, Filter), Req};
		    <<"HEAD">> ->
			{erocci_store:get(Path, Creds, Filter), Req};
		    _ ->
			{{error, method_not_allowed}, Req}
		end,
    {cowboy_rest, cors(<<"GET, DELETE, POST, PUT, OPTIONS, HEAD">>, Req1), S}.


-define(body_opts, [
		    {length, 64000},
		    {read_length, 64000},
		    {read_timeout, 5000}
		   ]).
parse(Req, Next) ->
    case cowboy_req:body(Req, ?body_opts) of
	{ok, Body, Req1} ->
	    {Next({cowboy_req:header(<<"content-type">>, Req1), Body}), Req1};
	{more, _, Req1} ->
	    {{error, badlength}, Req1}
    end.


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
	    {error, {parse_error, range}};
	  error:{badmatch, false} ->
	    {ok, 0, 0}
    end.


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
    [ trails:trail(Location, ?MODULE, {kind, C}, Map) | Acc ];

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
    [ trails:trail(Location, ?MODULE, {mixin, C}, Map) | Acc ].
