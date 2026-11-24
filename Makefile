V ?= v
BUILD_DIR ?= build
EXAMPLES = htk word vim draw widgets terminal spreadsheet
BINARIES = $(addprefix $(BUILD_DIR)/,$(EXAMPLES))
SOURCES = $(wildcard lib/*.v lib/*.h render/*.v) v.mod
VML_SOURCES = vml/main.v vml/parser.v vml/generator.v vml/vtk.vmlt
VML_EXAMPLES = hello preferences markdown widgets
VML_UIS = $(addsuffix /ui.v,$(addprefix vml/examples/,$(VML_EXAMPLES)))
VML_BINARIES = $(addprefix $(BUILD_DIR)/vml-,$(VML_EXAMPLES))

all: $(BINARIES) vml

$(BUILD_DIR)/%: examples/%.v $(SOURCES)
	mkdir -p $(BUILD_DIR)
	$(V) -o $@ $<

$(BUILD_DIR)/spreadsheet: $(wildcard examples/spread/*.v)

$(BUILD_DIR)/vmlc: $(VML_SOURCES)
	mkdir -p $(BUILD_DIR)
	$(V) -o $@ vml

$(VML_UIS): vml/examples/%/ui.v: vml/examples/%/ui.vml $(BUILD_DIR)/vmlc
	$(BUILD_DIR)/vmlc $<

$(VML_BINARIES): $(BUILD_DIR)/vml-%: vml/examples/%/ui.v vml/examples/%/main.v $(SOURCES)
	$(V) -o $@ vml/examples/$*

vml: $(BUILD_DIR)/vmlc $(VML_BINARIES)

test: $(VML_UIS)
	$(V) test .

check-windows: $(VML_UIS)
	@set -e; for example in $(EXAMPLES); do $(V) -os windows -check examples/$$example.v; done
	$(V) -os windows -check vml
	@set -e; for example in $(VML_EXAMPLES); do $(V) -os windows -check vml/examples/$$example; done

fmt:
	$(V) fmt -w .

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all vml test check-windows fmt clean
