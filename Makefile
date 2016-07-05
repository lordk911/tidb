### Makefile for tidb

# Ensure GOPATH is set before running build process.
ifeq "$(GOPATH)" ""
  $(error Please set the environment variable GOPATH before running `make`)
endif

path_to_add := $(addsuffix /bin,$(subst :,/bin:,$(GOPATH)))
export PATH := $(path_to_add):$(PATH)

# Check the version of make and set env varirables/commands accordingly.
version_list := $(subst ., ,$(MAKE_VERSION))
major_version := $(firstword $(version_list))
old_versions := 0 1 2 3
ifeq "$(major_version)" "$(filter $(major_version),$(old_versions))"
  # Old version of `make` installed. It fails to search golex/goyacc
  # by using the modified `PATH`, so we specify these commands with full path.
  GOLEX   = $$(which golex)
  GOYACC  = $$(which goyacc)
  GOLINT  = $$(which golint)
else
  # After version 4, `make` could follow modified `PATH` to find
  # golex/goyacc correctly.
  GOLEX   := golex
  GOYACC  := goyacc
  GOLINT  := golint
endif

GO        := GO15VENDOREXPERIMENT="1" go
ARCH      := "`uname -s`"
LINUX     := "Linux"
MAC       := "Darwin"
PACKAGES  := $$(go list ./...| grep -vE 'vendor')

LDFLAGS += -X "github.com/pingcap/tidb/util/printer.TiDBBuildTS=$(shell date -u '+%Y-%m-%d %I:%M:%S')"
LDFLAGS += -X "github.com/pingcap/tidb/util/printer.TiDBGitHash=$(shell git rev-parse HEAD)"

TARGET = ""

.PHONY: all build install update parser clean todo test gotest interpreter server

all: parser build test check

build:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) build
	rm -rf vendor

install:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) install ./...
	rm -rf vendor

TEMP_FILE = temp_parser_file

parser:
	go get github.com/tiancaiamao/goyacc
	go get github.com/qiuyesuifeng/golex
	$(GOYACC) -o /dev/null -xegen $(TEMP_FILE) parser/parser.y
	$(GOYACC) -o parser/parser.go -xe $(TEMP_FILE) parser/parser.y 2>&1 | egrep "(shift|reduce)/reduce" | awk '{print} END {if (NR > 0) {print "Find conflict in parser.y. Please check y.output for more information."; system("rm -f $(TEMP_FILE)"); exit 1;}}'
	rm -f $(TEMP_FILE)
	rm -f y.output

	@if [ $(ARCH) = $(LINUX) ]; \
	then \
		sed -i -e 's|//line.*||' -e 's/yyEofCode/yyEOFCode/' parser/parser.go; \
	elif [ $(ARCH) = $(MAC) ]; \
	then \
		/usr/bin/sed -i "" 's|//line.*||' parser/parser.go; \
		/usr/bin/sed -i "" 's/yyEofCode/yyEOFCode/' parser/parser.go; \
	fi

	$(GOLEX) -o parser/scanner.go parser/scanner.l
	@awk 'BEGIN{print "// Code generated by goyacc"} {print $0}' parser/parser.go > tmp_parser.go && mv tmp_parser.go parser/parser.go;
	@awk 'BEGIN{print "// Code generated by goyacc"} {print $0}' parser/scanner.go > tmp_scanner.go && mv tmp_scanner.go parser/scanner.go;

check:
	bash gitcookie.sh
	go get github.com/golang/lint/golint

	@echo "vet"
	@ go tool vet . 2>&1 | grep -vE 'vendor|parser/scanner.*unreachable code' | awk '{print} END{if(NR>0) {exit 1}}'
	@echo "vet --shadow"
	@ go tool vet --shadow . 2>&1 | grep -vE 'vendor|parser/parser.go|parser/scanner.go' | awk '{print} END{if(NR>0) {exit 1}}'
	@echo "golint"
	@ $(GOLINT) ./... 2>&1 | grep -vE 'vendor|LastInsertId|NewLexer|\.pb\.go' | awk '{print} END{if(NR>0) {exit 1}}'
	@echo "gofmt (simplify)"
	@ gofmt -s -l . 2>&1 | grep -vE 'vendor|parser/parser.go|parser/scanner.go' | awk '{print} END{if(NR>0) {exit 1}}'

errcheck:
	go get github.com/kisielk/errcheck
	errcheck -blank $(PACKAGES)

clean:
	$(GO) clean -i ./...
	rm -rf *.out

todo:
	@grep -n ^[[:space:]]*_[[:space:]]*=[[:space:]][[:alpha:]][[:alnum:]]* */*.go parser/scanner.l parser/parser.y || true
	@grep -n TODO */*.go parser/scanner.l parser/parser.y || true
	@grep -n BUG */*.go parser/scanner.l parser/parser.y || true
	@grep -n println */*.go parser/scanner.l parser/parser.y || true

test: gotest

gotest:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test -cover $(PACKAGES)
	rm -rf vendor

race:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test --race -cover $(PACKAGES)
	rm -rf vendor

ddl_test:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test ./ddl/... -skip_ddl=false
	rm -rf vendor

ddl_race_test:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test --race ./ddl/... -skip_ddl=false
	rm -rf vendor

tikv_integration_test:
	rm -rf vendor && ln -s _vendor/vendor vendor
	$(GO) test ./store/tikv/. -with-tikv=true
	rm -rf vendor

interpreter:
	rm -rf vendor && ln -s _vendor/vendor vendor
	@cd interpreter && $(GO) build -ldflags '$(LDFLAGS)'
	rm -rf vendor

server: parser
ifeq ($(TARGET), "")
	rm -rf vendor && ln -s _vendor/vendor vendor
	@cd tidb-server && $(GO) build -ldflags '$(LDFLAGS)'
	rm -rf vendor
else
	rm -rf vendor && ln -s _vendor/vendor vendor
	@cd tidb-server && $(GO) build -ldflags '$(LDFLAGS)' -o '$(TARGET)'
	rm -rf vendor
endif
