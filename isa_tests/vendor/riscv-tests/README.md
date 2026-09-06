Vendored, unmodified, from https://github.com/riscv-software-src/riscv-tests
commit 2ebecad997fa58cd9e5724340ba75aa4b59bd1d0 (2026-08-14).

Only the rv32ui sources, the rv64ui bodies they include, and
macros/scalar/test_macros.h are kept. The upstream `env/` directory is NOT
used: this core has no CSRs, so isa_tests/env/riscv_test.h replaces it.
License: BSD 3-clause, see LICENSE.
