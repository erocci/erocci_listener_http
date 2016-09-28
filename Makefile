version = 1.0

PROJECT = erocci_listener_http
PROJECT_VERSION = $(shell git describe --always --tags 2> /dev/null | sed -e 's/v\(.*\)/\1/' || echo $(version))

DEPS = occi erocci_core cowboy_swagger uri

dep_occi = git https://github.com/erocci/erlang-occi.git master
dep_erocci_core = git https://github.com/erocci/erocci_core.git next
dep_erocci_frontend = git https://github.com/erocci/erocci_frontend.git master
dep_cowboy_swagger = git https://github.com/jeanparpaillon/cowboy-swagger.git cowboy2
dep_uri = git https://github.com/erlware/uri.git 91f6b71

include erlang.mk
