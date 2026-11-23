V ?= v
BUILD_DIR ?= build
EXAMPLES = htk word vim draw widgets terminal
BINARIES = $(addprefix $(BUILD_DIR)/,$(EXAMPLES))
SOURCES = $(wildcard lib/*.v examples/support/*.v) v.mod
VML_SOURCES = vml/main.v vml/parser.v vml/generator.v vml/vtk.vmlt

all: $(BINARIES) vml

$(BUILD_DIR)/%: examples/%.v $(SOURCES)
	mkdir -p $(BUILD_DIR)
	$(V) -o $@ $<

$(BUILD_DIR)/vmlc: $(VML_SOURCES)
	mkdir -p $(BUILD_DIR)
	$(V) -o $@ vml

vml/examples/hello/ui.v: vml/examples/hello/ui.vml $(BUILD_DIR)/vmlc
	$(BUILD_DIR)/vmlc $<

$(BUILD_DIR)/vml-hello: vml/examples/hello/ui.v vml/examples/hello/main.v $(SOURCES)
	$(V) -o $@ vml/examples/hello

vml: $(BUILD_DIR)/vmlc $(BUILD_DIR)/vml-hello

test: vml/examples/hello/ui.v
	$(V) test .

check-windows: vml/examples/hello/ui.v
	@set -e; for example in $(EXAMPLES); do $(V) -os windows -check examples/$$example.v; done
	$(V) -os windows -check vml
	$(V) -os windows -check vml/examples/hello

fmt:
	$(V) fmt -w .

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all vml test check-windows fmt clean
