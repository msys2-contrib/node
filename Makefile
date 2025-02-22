-include config.mk

BUILDTYPE ?= Release
PYTHON ?= python
NINJA ?= ninja
DESTDIR ?=
SIGN ?=
PREFIX ?= /usr/local

# Determine EXEEXT
EXEEXT=$(shell $(PYTHON) -c "import sysconfig; print(sysconfig.get_config_var('EXE'))")

NODE ?= ./node$(EXEEXT)
NODE_EXE = node$(EXEEXT)
NODE_G_EXE = node_g$(EXEEXT)

# Default to verbose builds.
# To do quiet/pretty builds, run `make V=` to set V to an empty string,
# or set the V environment variable to an empty string.
V ?= 1

ifeq ($(USE_NINJA),1)
ifneq ($(V),)
NINJA := $(NINJA) -v
endif
endif

# BUILDTYPE=Debug builds both release and debug builds. If you want to compile
# just the debug build, run `make -C out BUILDTYPE=Debug` instead.
ifeq ($(BUILDTYPE),Release)
all: out/Makefile $(NODE_EXE)
else
all: out/Makefile $(NODE_EXE) $(NODE_G_EXE)
endif

# The .PHONY is needed to ensure that we recursively use the out/Makefile
# to check for changes.
.PHONY: $(NODE_EXE) $(NODE_G_EXE)

ifeq ($(USE_NINJA),1)
$(NODE_EXE): config.gypi
	$(NINJA) -C out/Release/
	ln -fs out/Release/$(NODE_EXE) $@

$(NODE_G_EXE): config.gypi
	$(NINJA) -C out/Debug/
	ln -fs out/Debug/$(NODE_EXE) $@
else
$(NODE_EXE): config.gypi out/Makefile
	$(MAKE) -C out BUILDTYPE=Release V=$(V)
	ln -fs out/Release/$(NODE_EXE) $@

$(NODE_G_EXE): config.gypi out/Makefile
	$(MAKE) -C out BUILDTYPE=Debug V=$(V)
	ln -fs out/Debug/$(NODE_EXE) $@
endif

out/Makefile: common.gypi deps/uv/uv.gyp deps/http_parser/http_parser.gyp deps/zlib/zlib.gyp deps/v8/build/toolchain.gypi deps/v8/build/features.gypi deps/v8/tools/gyp/v8.gyp node.gyp config.gypi
ifeq ($(USE_NINJA),1)
	touch out/Makefile
	$(PYTHON) tools/gyp_node.py -f ninja
else
	$(PYTHON) tools/gyp_node.py -f make
endif

config.gypi: configure
	if [ -f $@ ]; then
		$(error Stale $@, please re-run ./configure)
	else
		$(error No $@, please run ./configure first)
	fi

install: all
	$(PYTHON) tools/install.py $@ '$(DESTDIR)' '$(PREFIX)'

uninstall:
	$(PYTHON) tools/install.py $@ '$(DESTDIR)' '$(PREFIX)'

clean:
	-rm -rf out/Makefile $(NODE_EXE) $(NODE_G_EXE) out/$(BUILDTYPE)/$(NODE_EXE) blog.html email.md
	-find out/ -name '*.o' -o -name '*.a' | xargs rm -rf
	-rm -rf node_modules

distclean:
	-rm -rf out
	-rm -f config.gypi
	-rm -f config.mk
	-rm -rf $(NODE_EXE) $(NODE_G_EXE) blog.html email.md
	-rm -rf node_modules

test: all
	$(PYTHON) tools/test.py --mode=release simple message
	$(MAKE) jslint
	$(MAKE) cpplint

test-http1: all
	$(PYTHON) tools/test.py --mode=release --use-http1 simple message

test-valgrind: all
	$(PYTHON) tools/test.py --mode=release --valgrind simple message

test/gc/node_modules/weak/build/Release/weakref.node:
	@if [ ! -f $(NODE_EXE) ]; then make all; fi
	./$(NODE_EXE) deps/npm/node_modules/node-gyp/bin/node-gyp rebuild \
		--directory="$(shell pwd)/test/gc/node_modules/weak" \
		--nodedir="$(shell pwd)"

build-addons:
	@if [ ! -f node ]; then make all; fi
	rm -rf test/addons/doc-*/
	./node tools/doc/addon-verify.js
	$(foreach dir, \
			$(sort $(dir $(wildcard test/addons/*/*.gyp))), \
			./node deps/npm/node_modules/node-gyp/bin/node-gyp rebuild \
					--directory="$(shell pwd)/$(dir)" \
					--nodedir="$(shell pwd)" && ) echo "build done"

test-gc: all test/gc/node_modules/weak/build/Release/weakref.node
	$(PYTHON) tools/test.py --mode=release gc

test-build: all build-addons

test-all: test-build test/gc/node_modules/weak/build/Release/weakref.node
	$(PYTHON) tools/test.py --mode=debug,release
	make test-npm

test-all-http1: test-build
	$(PYTHON) tools/test.py --mode=debug,release --use-http1

test-all-valgrind: test-build
	$(PYTHON) tools/test.py --mode=debug,release --valgrind

test-release: test-build
	$(PYTHON) tools/test.py --mode=release

test-debug: test-build
	$(PYTHON) tools/test.py --mode=debug

test-message: test-build
	$(PYTHON) tools/test.py message

test-simple: all
	$(PYTHON) tools/test.py simple

test-pummel: all wrk
	$(PYTHON) tools/test.py pummel

test-internet: all
	$(PYTHON) tools/test.py internet

test-debugger: all
	$(PYTHON) tools/test.py debugger

test-npm: $(NODE_EXE)
	./$(NODE_EXE) deps/npm/test/run.js

test-npm-publish: $(NODE_EXE)
	npm_package_config_publishtest=true ./$(NODE_EXE) deps/npm/test/run.js

test-addons: test-build
	$(PYTHON) tools/test.py --mode=release addons

test-timers:
	$(MAKE) --directory=tools faketime
	$(PYTHON) tools/test.py --mode=release timers

test-timers-clean:
	$(MAKE) --directory=tools clean

apidoc_sources = $(wildcard doc/api/*.markdown)
apidocs = $(addprefix out/,$(apidoc_sources:.markdown=.html)) \
          $(addprefix out/,$(apidoc_sources:.markdown=.json))

apidoc_dirs = out/doc out/doc/api/ out/doc/api/assets

apiassets = $(subst api_assets,api/assets,$(addprefix out/,$(wildcard doc/api_assets/*)))

website_files = \
	out/doc/sh_main.js    \
	out/doc/sh_javascript.min.js

doc: $(apidoc_dirs) $(website_files) $(apiassets) $(apidocs) tools/doc/ out/doc/changelog.html $(NODE_EXE)

$(apidoc_dirs):
	mkdir -p $@

out/doc/api/assets/%: doc/api_assets/% out/doc/api/assets/
	cp $< $@

out/doc/changelog.html: ChangeLog doc/changelog-head.html doc/changelog-foot.html tools/build-changelog.sh $(NODE_EXE)
	bash tools/build-changelog.sh

out/doc/%: doc/%
	cp -r $< $@

out/doc/api/%.json: doc/api/%.markdown $(NODE_EXE)
	out/Release/$(NODE_EXE) tools/doc/generate.js --format=json $< > $@

out/doc/api/%.html: doc/api/%.markdown $(NODE_EXE)
	out/Release/$(NODE_EXE) tools/doc/generate.js --format=html --template=doc/template.html $< > $@

email.md: ChangeLog tools/email-footer.md
	bash tools/changelog-head.sh | sed 's|^\* #|* \\#|g' > $@
	cat tools/email-footer.md | sed -e 's|__VERSION__|'$(VERSION)'|g' >> $@

blog.html: email.md
	cat $< | ./$(NODE_EXE) tools/doc/node_modules/.bin/marked > $@

website-upload: doc
	rsync -r out/doc/ node@nodejs.org:~/web/nodejs.org/
	ssh node@nodejs.org '\
    rm -f ~/web/nodejs.org/dist/latest &&\
    ln -s $(VERSION) ~/web/nodejs.org/dist/latest &&\
    rm -f ~/web/nodejs.org/docs/latest &&\
    ln -s $(VERSION) ~/web/nodejs.org/docs/latest &&\
    rm -f ~/web/nodejs.org/dist/node-latest.tar.gz &&\
    ln -s $(VERSION)/node-$(VERSION).tar.gz ~/web/nodejs.org/dist/node-latest.tar.gz'

docopen: out/doc/api/all.html
	-google-chrome out/doc/api/all.html

docclean:
	-rm -rf out/doc

RAWVER=$(shell $(PYTHON) tools/getnodeversion.py)
VERSION=v$(RAWVER)
RELEASE=$(shell $(PYTHON) tools/getnodeisrelease.py)
PLATFORM=$(shell uname | tr '[:upper:]' '[:lower:]')
ifeq ($(findstring x86_64,$(shell uname -m)),x86_64)
DESTCPU ?= x64
else
DESTCPU ?= ia32
endif
ifeq ($(DESTCPU),x64)
ARCH=x64
else
ifeq ($(DESTCPU),arm)
ARCH=arm
else
ARCH=x86
endif
endif
TARNAME=node-$(VERSION)
ifdef NIGHTLY
TAG = nightly-$(NIGHTLY)
TARNAME=node-$(VERSION)-$(TAG)
endif
TARBALL=$(TARNAME).tar.gz
BINARYNAME=$(TARNAME)-$(PLATFORM)-$(ARCH)
BINARYTAR=$(BINARYNAME).tar.gz
PKG=out/$(TARNAME).pkg
packagemaker=/Developer/Applications/Utilities/PackageMaker.app/Contents/MacOS/PackageMaker

PKGSRC=nodejs-$(DESTCPU)-$(RAWVER).tgz
ifdef NIGHTLY
PKGSRC=nodejs-$(DESTCPU)-$(RAWVER)-$(TAG).tgz
endif

dist: doc $(TARBALL) $(PKG)

PKGDIR=out/dist-osx

release-only:
	@if [ "$(shell git status --porcelain | egrep -v '^\?\? ')" = "" ]; then \
		exit 0 ; \
	else \
	  echo "" >&2 ; \
		echo "The git repository is not clean." >&2 ; \
		echo "Please commit changes before building release tarball." >&2 ; \
		echo "" >&2 ; \
		git status --porcelain | egrep -v '^\?\?' >&2 ; \
		echo "" >&2 ; \
		exit 1 ; \
	fi
	@if [ "$(NIGHTLY)" != "" -o "$(RELEASE)" = "1" ]; then \
		exit 0; \
	else \
	  echo "" >&2 ; \
		echo "#NODE_VERSION_IS_RELEASE is set to $(RELEASE)." >&2 ; \
	  echo "Did you remember to update src/node_version.cc?" >&2 ; \
	  echo "" >&2 ; \
		exit 1 ; \
	fi

pkg: $(PKG)

$(PKG): release-only
	rm -rf $(PKGDIR)
	rm -rf out/deps out/Release
	$(PYTHON) ./configure --without-snapshot --dest-cpu=ia32 --tag=$(TAG)
	$(MAKE) install V=$(V) DESTDIR=$(PKGDIR)/32
	rm -rf out/deps out/Release
	$(PYTHON) ./configure --without-snapshot --dest-cpu=x64 --tag=$(TAG)
	$(MAKE) install V=$(V) DESTDIR=$(PKGDIR)
	SIGN="$(APP_SIGN)" PKGDIR="$(PKGDIR)" bash tools/osx-codesign.sh
	lipo $(PKGDIR)/32/usr/local/bin/node \
		$(PKGDIR)/usr/local/bin/node \
		-output $(PKGDIR)/usr/local/bin/node-universal \
		-create
	mv $(PKGDIR)/usr/local/bin/node-universal $(PKGDIR)/usr/local/bin/node
	rm -rf $(PKGDIR)/32
	$(packagemaker) \
		--id "org.nodejs.Node" \
		--doc tools/osx-pkg.pmdoc \
		--out $(PKG)
	SIGN="$(INT_SIGN)" PKG="$(PKG)" bash tools/osx-productsign.sh

$(TARBALL): release-only $(NODE_EXE) doc
	git archive --format=tar --prefix=$(TARNAME)/ HEAD | tar xf -
	mkdir -p $(TARNAME)/doc/api
	cp doc/node.1 $(TARNAME)/doc/node.1
	cp -r out/doc/api/* $(TARNAME)/doc/api/
	rm -rf $(TARNAME)/deps/v8/test # too big
	rm -rf $(TARNAME)/doc/images # too big
	find $(TARNAME)/ -type l | xargs rm # annoying on windows
	tar -cf $(TARNAME).tar $(TARNAME)
	rm -rf $(TARNAME)
	gzip -f -9 $(TARNAME).tar

tar: $(TARBALL)

$(BINARYTAR): release-only
	rm -rf $(BINARYNAME)
	rm -rf out/deps out/Release
	$(PYTHON) ./configure --prefix=/ --without-snapshot --dest-cpu=$(DESTCPU) --tag=$(TAG) $(CONFIG_FLAGS)
	$(MAKE) install DESTDIR=$(BINARYNAME) V=$(V) PORTABLE=1
	cp README.md $(BINARYNAME)
	cp LICENSE $(BINARYNAME)
	cp ChangeLog $(BINARYNAME)
	tar -cf $(BINARYNAME).tar $(BINARYNAME)
	rm -rf $(BINARYNAME)
	gzip -f -9 $(BINARYNAME).tar

binary: $(BINARYTAR)

$(PKGSRC): release-only
	rm -rf dist out
	$(PYTHON) configure --prefix=/ --without-snapshot \
		--dest-cpu=$(DESTCPU) --tag=$(TAG) $(CONFIG_FLAGS)
	$(MAKE) install DESTDIR=dist
	(cd dist; find * -type f | sort) > packlist
	pkg_info -X pkg_install | \
		egrep '^(MACHINE_ARCH|OPSYS|OS_VERSION|PKGTOOLS_VERSION)' > build-info
	pkg_create -B build-info -c tools/pkgsrc/comment -d tools/pkgsrc/description \
		-f packlist -I /opt/local -p dist -U $(PKGSRC)

pkgsrc: $(PKGSRC)

dist-upload: $(TARBALL) $(PKG)
	ssh node@nodejs.org mkdir -p web/nodejs.org/dist/$(VERSION)
	scp $(TARBALL) node@nodejs.org:~/web/nodejs.org/dist/$(VERSION)/$(TARBALL)
	scp $(PKG) node@nodejs.org:~/web/nodejs.org/dist/$(VERSION)/$(TARNAME).pkg

wrkclean:
	$(MAKE) -C tools/wrk/ clean
	rm tools/wrk/wrk

wrk: tools/wrk/wrk
tools/wrk/wrk:
	$(MAKE) -C tools/wrk/

bench-net: all
	@$(NODE) benchmark/common.js net

bench-crypto: all
	@$(NODE) benchmark/common.js crypto

bench-tls: all
	@$(NODE) benchmark/common.js tls

bench-http: wrk all
	@$(NODE) benchmark/common.js http

bench-fs: all
	@$(NODE) benchmark/common.js fs

bench-misc: all
	@$(MAKE) -C benchmark/misc/function_call/
	@$(NODE) benchmark/common.js misc

bench-array: all
	@$(NODE) benchmark/common.js arrays

bench-buffer: all
	@$(NODE) benchmark/common.js buffers

bench-all: bench bench-misc bench-array bench-buffer

bench: bench-net bench-http bench-fs bench-tls

bench-http-simple:
	 benchmark/http_simple_bench.sh

bench-idle:
	./$(NODE_EXE) benchmark/idle_server.js &
	sleep 1
	./$(NODE_EXE) benchmark/idle_clients.js &

jslintfix:
	PYTHONPATH=tools/closure_linter/ $(PYTHON) tools/closure_linter/closure_linter/fixjsstyle.py --strict --nojsdoc -r lib/ -r src/ --exclude_files lib/punycode.js

jslint:
	PYTHONPATH=tools/closure_linter/ $(PYTHON) tools/closure_linter/closure_linter/gjslint.py --unix_mode --strict --nojsdoc -r lib/ -r src/ --exclude_files lib/punycode.js

CPPLINT_EXCLUDE ?=
CPPLINT_EXCLUDE += src/node_dtrace.cc
CPPLINT_EXCLUDE += src/node_dtrace.cc
CPPLINT_EXCLUDE += src/node_root_certs.h
CPPLINT_EXCLUDE += src/node_win32_perfctr_provider.cc
CPPLINT_EXCLUDE += src/queue.h
CPPLINT_EXCLUDE += src/tree.h
CPPLINT_EXCLUDE += src/v8abbr.h

CPPLINT_FILES = $(filter-out $(CPPLINT_EXCLUDE), $(wildcard src/*.cc src/*.h src/*.c))

cpplint:
	@$(PYTHON) tools/cpplint.py $(CPPLINT_FILES)

lint: jslint cpplint

.PHONY: lint cpplint jslint bench clean docopen docclean doc dist distclean check uninstall install install-includes install-bin all staticlib dynamiclib test test-all test-addons build-addons website-upload pkg blog blogclean tar binary release-only bench-http-simple bench-idle bench-all bench bench-misc bench-array bench-buffer bench-net bench-http bench-fs bench-tls
