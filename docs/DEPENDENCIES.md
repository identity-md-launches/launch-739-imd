# Vendored dependencies

These files were copied from the worker's provided local mirrors. They are
ordinary source files, not submodules, and require no fetch during verification.
No upstream source changes were made.

| Library | Mirror package version | Included files |
| --- | --- | --- |
| OpenZeppelin Contracts | `5.7.0` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `IERC6093.sol`, MIT license |
| forge-std | `1.16.2` | `src/`, MIT and Apache-2.0 licenses |

Package versions identify the local mirror metadata; they are not a claim about
the current upstream release. OpenZeppelin's individual source headers retain
their own last-updated version labels. Production IMD imports only the ERC-20
dependency closure; forge-std is used by tests and the deployment script.

The exact vendored bytes are pinned in [DEPENDENCIES.sha256](DEPENDENCIES.sha256).
Check them from the repository root with:

```sh
sha256sum --check docs/DEPENDENCIES.sha256
```
