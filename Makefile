.PHONY: test test-file deps

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
