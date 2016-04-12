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
         allow_missing_post/2,
         is_authorized/2,
         resource_exists/2,
         is_conflict/2,
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
	    init_node(Path, Creds, Filter, Req2)
    end.


init_capabilities(Creds, Filter, Req) ->
    {cowboy_rest, Req, erocci_store:capabilities(Creds, Filter, cowboy_req:url(Req))}.


init_node(Path, Creds, Filter, Req) ->
    {cowboy_rest, Req, erocci_store:find(Path, Creds, Filter, cowboy_req:url(Req))}.


allowed_methods(Req, {error, not_found}=S) ->
    Methods = [<<"GET">>, <<"OPTIONS">>, <<"HEAD">>],
    set_allowed_methods(Methods, Req, S);

allowed_methods(Req, {error, _}=S) ->
    Methods = [<<"GET">>, <<"DELETE">>, <<"OPTIONS">>, <<"POST">>, <<"PUT">>, <<"HEAD">>],
    set_allowed_methods(Methods, Req, S);

allowed_methods(Req, {ok, Node}=S) ->
    Methods = case erocci_node:type(Node) of
		  capabilities ->
		      [<<"GET">>, <<"DELETE">>, <<"OPTIONS">>, <<"POST">>, <<"HEAD">>];
		  {collection, kind} ->
		      [<<"GET">>, <<"DELETE">>, <<"OPTIONS">>, <<"POST">>, <<"HEAD">>];
		  _ ->
		      [<<"GET">>, <<"DELETE">>, <<"OPTIONS">>, <<"POST">>, <<"PUT">>, <<"HEAD">>]
	      end,
    set_allowed_methods(Methods, Req, S).


content_types_provided(Req, {ok, Node}=S) ->
    CT = [
	  {{<<"text">>,            <<"plain">>,     []}, to},
	  {{<<"text">>,            <<"occi">>,      []}, to},
	  {{<<"application">>,     <<"json">>,      []}, to},
	  {{<<"application">>,     <<"occi+json">>, []}, to},
	  {{<<"application">>,     <<"xml">>,       []}, to},
	  {{<<"application">>,     <<"occi+xml">>,  []}, to}
	 ],
    CT1 = case erocci_node:type(Node) of
	      capabilities -> 
		  [ {{<<"text">>,            <<"uri-list">>,  []}, to} | CT ];
	      {collection, _} ->
		  [ {{<<"text">>,            <<"uri-list">>,  []}, to} | CT ];
	      _ ->
		  CT
	  end,
    {CT1, Req, S};

content_types_provided(Req, {error, _}=S) ->
    CT = [
	  {{<<"text">>,            <<"plain">>,     []}, to},
	  {{<<"text">>,            <<"occi">>,      []}, to},
	  {{<<"application">>,     <<"json">>,      []}, to},
	  {{<<"application">>,     <<"occi+json">>, []}, to},
	  {{<<"application">>,     <<"xml">>,       []}, to},
	  {{<<"application">>,     <<"occi+xml">>,  []}, to},
	  {{<<"text">>,            <<"uri-list">>,  []}, to}
	 ],
    {CT, Req, S}.


content_types_accepted(Req, State) ->
    {[
      {{<<"text">>,            <<"plain">>,     []}, from},
      {{<<"text">>,            <<"occi">>,      []}, from},
      {{<<"application">>,     <<"json">>,      []}, from},
      {{<<"application">>,     <<"occi+json">>, []}, from},
      {{<<"application">>,     <<"xml">>,       []}, from},
      {{<<"application">>,     <<"occi+xml">>,  []}, from}
     ],
     Req, State}.


allow_missing_post(Req, S) ->
    {false, Req, S}.


resource_exists(Req, {error, not_found}=S) ->
    {false, Req, S};

resource_exists(Req, S) ->
    {true, Req, S}.


is_authorized(Req, {error, {unauthorized, Auth}}=S) ->
    {{false, Auth}, Req, S};

is_authorized(Req, S) ->
    {true, Req, S}.


is_conflict(Req, {ok, Node}=S) ->
    {entity =:= erocci_node:type(Node), Req, S};

is_conflict(Req, S) ->
    {false, Req, S}.


delete_resource(Req, {ok, Node}=S) ->
    Mimetype = cowboy_req:header(<<"accept">>, Req),
    case erocci_node:type(Node) of
	capabilities ->
	    delete_mixin(Mimetype, Req, S);
	{collection, kind} ->
	    delete(Mimetype, Req, S);
	{collection, mixin} ->
	    disassociate(Mimetype, Req, S);
	_ ->
	    delete(Mimetype, Req, S)
    end.


to(Req, {error, Err}=S) ->
    ?error("HTTP listener error: ~p~n", [Err]),
    {halt, Req, S};

to(Req, {ok, Node}=S) ->
    Obj = case erocci_node:type(Node) of
	      {collection, _} ->
		  %% @todo parse limits
		  Start = 0,
		  Limit = undefined,
		  erocci_store:load_collection(Node, Start, Limit);
	      _ ->
		  erocci_store:load(Node)
	  end,
    Body = occi_rendering:render(cowboy_req:header(<<"accept">>), Obj),
    {[Body, "\n"], Req, S}.


from(Req, S) ->
    Mimetype = cowboy_req:header(<<"accept">>, Req),
    try occi_rendering:parse(Mimetype, cowboy_req:body(Req)) of
	Obj ->
	    case cowboy_req:method(Req) of
		<<"PUT">> ->
		    save(Mimetype, Obj, Req, S);
		<<"POST">> ->
		    case cowboy_req:match_qs([action], Req) of
			#{ action := Action } ->
			    action(Mimetype, Action, Obj, Req, S);
			_ ->
			    update(Mimetype, Obj, Req, S)
		    end;
		Method ->
		    throw({invalid_method, Method})
	    end
    catch throw:{parse_error, Err} ->
	    Req2 = errors(400, {parse_error, Err}, Mimetype, Err),
	    {halt, Req2, S}
    end.


%% @doc Return trail definitions
%% @end
-define(trails_mimetypes, ["text/plain", "text/occi", "application/occi+json", 
			   "application/json", "applicaton/occi+xml", "applicaton/xml"]).
trails() ->
    Query = trails:trail("/-/", ?MODULE, [],
			 #{get =>
			       #{ tags => ["capabilities"],
				  description => "Retrieve Category instances",
				  consumes => [],
				  produces => [ "text/uri-list" | ?trails_mimetypes ]
				},
			   post =>
			       #{ tags => ["capabilities"],
				  description => "Add a user-defined Mixin instance",
				  consumes => ?trails_mimetypes,
				  produces => []},
			   delete =>
			       #{ tags => ["capabilities"],
				  description => "Remove a user-defined Mixin instance",
				  consumes => ?trails_mimetypes,
				  produces => []}
			  }),
    [ Query | [ category_metadata(occi_category:class(C), C) 
		|| C <- erocci_store:capabilities() ]].

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
delete_mixin(Mimetype, Req, S) ->
    try occi_rendering:parse(Mimetype) of
	Obj ->
	    case erocci_store:delete_mixin(Obj) of
		ok ->
		    {true, Req, S};
		{error, _}=Err ->
		    Req2 = errors(Err, Mimetype, Req),
		    {false, Req2, S}
	    end
    catch throw:{parse_error, Err} ->
	    Req2 = errors(400, {parse_error, Err}, Mimetype, Req),
	    {halt, Req2, S}
    end.


delete(Mimetype, Req, {ok, Node}=S) ->
    case erocci_store:delete(Node) of
	ok ->
	    {true, Req, S};
	{error, _}=Err ->
	    Req2 = errors(Err, Mimetype, Req),
	    {false, Req2, S}
    end.


disassociate(Mimetype, Req, {ok, Node}=S) ->
    try occi_rendering:parse(Mimetype) of
	Obj ->
	    case erocci_store:disassociate(Obj, Node) of
		ok ->
		    {true, Req, S};
		{error, _}=Err ->
		    Req2 = errors(Err, Mimetype, Req),
		    {false, Req2, S}
	    end
    catch throw:{parse_error, Err} ->
	    Req2 = errors(400, {parse_error, Err}, Mimetype, Req),
	    {halt, Req2, S}
    end.    
    

save(Mimetype, Obj, Req, {error, not_found}=S) ->
    Ret = erocci_store:save(Obj, cowboy_req:url(Req)),
    end_from(Ret, Mimetype, Req, S);

save(Mimetype, Obj, Req, {ok, Node}=S) ->
    case erocci_node:type(Node) of
	{collection, mixin} ->
	    Ret = erocci_store:associate(Obj, Node),
	    end_from(Ret, Mimetype, Req, S);
	entity ->
	    Ret = erocci_store:save(Obj, cowboy_req:url(Req)),
	    end_from(Ret, Mimetype, Req, S)
    end.


update(Mimetype, Obj, Req, {ok, Node}=S) ->
    case erocci_node:type(Node) of
	capabilites ->
	    Ret = erocci_store:add_mixin(Obj, Node),
	    end_from(Ret, Mimetype, Req, S);
	entity ->
	    Ret = erocci_store:update(Obj, Node),
	    end_from(Ret, Mimetype, Req, S);
	{collection, kind} ->
	    Ret = erocci_store:save(Obj, Node),
	    end_from(Ret, Mimetype, Req, S);
	{collection, mixin} ->
	    Ret = erocci_store:full_associate(Obj, Node),
	    end_from(Ret, Mimetype, Req, S)
    end.


action(Mimetype, Action, Invoke, Req, {ok, Node}=S) ->
    Ret = erocci_store:action(Action, Invoke, Node),
    end_from(Ret, Mimetype, Req, S).


end_from(ok, _Mimetype, Req, S) ->
    {true, Req, S};

end_from({ok, Obj}, Mimetype, Req, S) ->
    Body = occi_rendering:render(Mimetype, Obj),
    {true, cowboy_req:set_resp_body(Body, Req), S};

end_from({error, Err}, Mimetype, Req, S) ->
    Body = erocci_errors:render(Mimetype, Err),
    {false, cowboy_req:set_resp_body(Body, Req, S), S}.


set_allowed_methods(Methods, Req, Node) ->
    << ", ", Allow/binary >> = << << ", ", M/binary >> || M <- Methods >>,
    {Methods, occi_http_common:set_cors(Req, Allow), Node}.


credentials(Req) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
	{<<"basic">>, {User, Password}} ->
	    erocci_creds:basic(User, Password);
	_ ->
	    erocci_creds:anonymous()
    end.


parse_filters(Qs) ->
    case parse_filters(Qs, []) of
	[] ->
	    undefined;
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
    case binary:split(uri:unquote(Bin), <<"#">>) of
        [Scheme, Term] -> {Scheme, Term};
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


errors(Err, Mimetype, Req) ->
    Body = erocci_errors:render(Err, Mimetype),
    cowboy_req:set_resp_body(Body, Req).


errors(Status, Err, Mimetypes, Req) ->
    Req2 = errors(Err, Mimetypes, Req),
    cowboy_req:reply(Status, Req2).


category_metadata(kind, C) ->
    {Scheme, Term} = occi_category:id(C),
    Name = io_lib:format("~s~s", [Scheme, Term]),
    Title = occi_category:title(C),
    Map = #{ get => 
		 #{ tags => ["category", "kind", Name],
		    description => 
			io_lib:format("Retrieve the collection of entities of the kind ~s (~s)",
				      [Name, Title]),
		    consumes => [],
		    produces => [ "text/uri-list" | ?trails_mimetypes ]},
	     post => 
		 #{ tags => ["category", "kind", Name],
		    description => 
			io_lib:format("Creates a new entity the kind ~s (~s)",
				      [Name, Title]),
		    consumes => ?trails_mimetypes,
		    produces => ?trails_mimetypes},
	     delete => 
		 #{ tags => ["category", "kind", Name],
		    descriptionn =>
			io_lib:format("Remove entities of the kind ~s (~s)", [Name, Title]),
		    consumes => [],
		    produces => []}},
    trails:trail(occi_category:location(C), ?MODULE, [], Map);

category_metadata(mixin, C) ->
    {Scheme, Term} = occi_category:id(C),
    Name = io_lib:format("~s~s", [Scheme, Term]),
    Title = occi_category:title(C),
    Map = #{ get => 
		 #{ tags => ["category", "mixin", Name],
		    description => 
			io_lib:format("Retrieve the collection of entities associated with mixin ~s (~s)",
				      [Name, Title]),
		    consumes => [],
		    produces => [ "text/uri-list" | ?trails_mimetypes ]},
	     put => 
		 #{ tags => ["category", "mixin", Name],
		    description => 
			io_lib:format("Set the full collection of entities associated with mixin ~s (~s)",
				      [Name, Title]),
		    consumes => ?trails_mimetypes,
		    produces => ?trails_mimetypes},
	     post => 
		 #{ tags => ["category", "mixin", Name],
		    description => 
			io_lib:format("Add entities to the collection of entities associated with mixin ~s (~s)",
				      [Name, Title]),
		    consumes => ?trails_mimetypes,
		    produces => ?trails_mimetypes},
	     delete => 
		 #{ tags => ["category", "kind", Name],
		    descriptionn =>
			io_lib:format("Remove entities from the mixin collection ~s (~s)", 
				      [Name, Title]),
		    consumes => [],
		    produces => []}},
    trails:trail(occi_category:location(C), ?MODULE, [], Map).
