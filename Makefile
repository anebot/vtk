V ?= v
BUILD_DIR ?= build
EXAMPLES = htk word vim draw widgets terminal
BINARIES = $(addprefix $(BUILD_DIR)/,$(EXAMPLES))
SOURCES = $(wildcard *.v examples/support/*.v) v.mod

all: $(BINARIES)

$(BUILD_DIR)/%: examples/%.v $(SOURCES)
	mkdir -p $(BUILD_DIR)
	$(V) -o $@ $<

test:
	$(V) test .

check-windows:
	@set -e; for example in $(EXAMPLES); do $(V) -os windows -check examples/$$example.v; done

fmt:
	$(V) fmt -w .

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all test check-windows fmt clean
