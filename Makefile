.PHONY: check lint format format-check test test-file deps

LUA_DIRS := lua plugin tests

# Everything CI should gate on: lint + formatting + tests.
check: lint format-check test

# Lint for correctness (unused/undefined/shadowed).
lint:
	luacheck $(LUA_DIRS)

# Format in place.
format:
	stylua $(LUA_DIRS)

# Fail if anything is unformatted (CI).
format-check:
	stylua --check $(LUA_DIRS)

# Run the full mini.test suite headless. Bootstraps deps/ on first run.
test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run()"

# Run a single file: make test-file FILE=tests/test_analyze.lua
test-file: deps
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run_file('$(FILE)')"

# Clone test dependencies (mini.nvim) if absent.
deps:
	@test -d deps/mini.nvim || git clone --filter=blob:none --depth 1 \
		https://github.com/echasnovski/mini.nvim deps/mini.nvim

# --- Treesitter parsers ------------------------------------------------------
# Compile the typescript + tsx parsers into deps/ from the committed grammar
# sources. Reproducible and self-contained (no nvim-treesitter), so CI — which
# has no pre-installed parsers — can build them. Local devs whose runtimepath
# already carries these parsers don't need this; minimal_init.lua prefers the
# repo-local build and falls back to the standard Neovim data dir.
GRAMMAR_TAG := v0.23.2
GRAMMAR_SRC := deps/tree-sitter-typescript
PARSER_DIR  := deps/parsers/parser

.PHONY: parsers
parsers: $(PARSER_DIR)/typescript.so $(PARSER_DIR)/tsx.so

$(GRAMMAR_SRC):
	git clone --filter=blob:none --depth 1 --branch $(GRAMMAR_TAG) \
		https://github.com/tree-sitter/tree-sitter-typescript $(GRAMMAR_SRC)

$(PARSER_DIR)/typescript.so: $(GRAMMAR_SRC)
	@mkdir -p $(PARSER_DIR)
	cc -o $@ -shared -fPIC -Os -I $(GRAMMAR_SRC)/typescript/src \
		$(GRAMMAR_SRC)/typescript/src/parser.c $(GRAMMAR_SRC)/typescript/src/scanner.c

$(PARSER_DIR)/tsx.so: $(GRAMMAR_SRC)
	@mkdir -p $(PARSER_DIR)
	cc -o $@ -shared -fPIC -Os -I $(GRAMMAR_SRC)/tsx/src \
		$(GRAMMAR_SRC)/tsx/src/parser.c $(GRAMMAR_SRC)/tsx/src/scanner.c
