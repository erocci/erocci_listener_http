version = 0.1

PROJECT = erocci_listener_http
PROJECT_VERSION = $(shell git describe --always --tags 2> /dev/null || echo $(version))

DEPS = erocci_core cowboy cowboy_swagger erocci_authnz erocci_backend_mnesia
dep_erocci_core = git https://github.com/erocci/erocci_core.git master
dep_erocci_backend_mnesia = git https://github.com/erocci/erocci_backend_mnesia.git master
dep_erocci_authnz = git https://github.com/erocci/erocci_authnz.git master
dep_cowboy = git https://github.com/ninenines/cowboy.git 1.0.3
dep_cowboy_swagger = git https://github.com/inaka/cowboy-swagger.git 1.0.3

include erlang.mk

fetch: $(ALL_DEPS_DIRS)
	for d in $(ALL_DEPS_DIRS); do \
	  $(MAKE) -C $$d $@ || true; \
	done

.PHONY: fetch
