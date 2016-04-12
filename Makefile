version = 0.1

PROJECT = erocci_listener_http
PROJECT_VERSION = $(shell git describe --always --tags 2> /dev/null || echo $(version))

DEPS = occi erocci_core cowboy_swagger
dep_occi = git https://github.com/erocci/erlang-occi.git master
dep_erocci_core = git https://github.com/erocci/erocci_core.git erlang-occi-integration
dep_cowboy_swagger = git https://github.com/jeanparpaillon/cowboy-swagger.git cowboy2

include erlang.mk

fetch: $(ALL_DEPS_DIRS)
	for d in $(ALL_DEPS_DIRS); do \
	  $(MAKE) -C $$d $@ || true; \
	done

.PHONY: fetch
