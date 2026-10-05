# IMD token

`src/IMD.sol:IMD` is an immutable, standard ERC-20 token. Its constructor takes
**no arguments** and mints the full supply once to `msg.sender`.

| Parameter | Value |
| --- | --- |
| Name | `IMD` |
| Symbol | `IMD` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000 IMD` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | `[]` |
| Intended launch chain | Sepolia, chain ID `11155111` |

## Behavior and assumptions

The request specifies a fixed supply and no special transfer rules, so this
implementation uses the vendored OpenZeppelin ERC-20 without transfer overrides.
Transfers deliver the exact requested amount. There are no fees, rebases,
subsequent mints, public burns, pause controls, blocklists, owner roles, proxies,
or upgrades. The deploying address gets tokens but no administrative authority.

Deployment through a factory credits that factory, **not** the transaction
originator. Distribution, liquidity provisioning, and contributor allocations
belong to the launch infrastructure; the token constructor performs none of
them. This deliverable does not choose pool parameters or create a launch
manifest.

The interface includes `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`,
`transfer`, `allowance`, `approve`, and `transferFrom`. Successful writes return
`true`; invalid operations revert with the ERC-6093 errors in the vendored
interface. Constructor minting and transfers emit `Transfer`; `approve` emits
`Approval`. Spending an allowance does not emit another `Approval` event.

Transfers of zero tokens and self-transfers are supported. The zero address is
rejected as a transfer recipient or approval spender. Finite allowances decrease
when spent; an allowance of `type(uint256).max` remains unchanged. Approvals
replace the previous allowance and can be revoked with zero. Holders should
approve only what is needed; when replacing an outstanding approval, revoke it
and confirm that transaction before granting a new one to reduce the standard
ERC-20 allowance-change race. Already-executed spending cannot be undone.

## Reproducible local checks

Foundry 1.8.3 and cached Solidity 0.8.26 are the toolchain. All Solidity
dependencies are ordinary files in `lib/`; no submodules, package installation,
network calls, environment configuration, or forks are needed to build and test.
The compiler is version-pinned, optimizer runs are 200, the EVM target is Paris,
and the metadata bytecode hash is disabled. FFI and filesystem permissions are
disabled. See [dependency provenance](docs/DEPENDENCIES.md).

```sh
forge build --offline
forge test --offline
forge fmt --check
forge test --offline --fuzz-seed 0x123456789abcdef --fuzz-runs 2048
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
```

The last command is a local deployment simulation, with no RPC or broadcast.
Tests pass explicit script configuration and never read or mutate environment
variables. Tests cover metadata, mint recipient and event, transfers, allowances,
reverts and atomic rollback, exact distribution amounts, rejected privileged
calls, runtime opcode restrictions, and supply conservation. Stateful invariants
exercise transfers and approvals among three actors across 8,192 calls per run.
The local pool-custody test checks token transfer accounting; it does not deploy
a Uniswap pool or claim to replace the protected launch integration harness.

## Deployment and operation

For the network launch, the network's reviewed factory deploys
`src/IMD.sol:IMD` using its creation bytecode and no appended constructor
arguments. The factory must receive exactly `10^27` base units before it
distributes any tokens. The subsequent manifest/integration step must use the
same artifact, empty constructor arguments, metadata, and exact supply above.

`script/Deploy.s.sol:Deploy` also supports standalone deployments. It reads only
the optional `EXPECTED_CHAIN_ID`; zero skips equality checking, while the script
always restricts the actual chain to local chain `31337` or Sepolia `11155111`.
It creates exactly one token between broadcast markers. In standalone use the
broadcasting deployer receives the supply. This route is appropriate for local
simulation, and is distinct from the factory route required for network launch.

Only the network operator is responsible for production transaction submission,
selecting and checking chain/factory/pool addresses, reviewing creation code and
the final manifest, arranging independent review, verifying deployed source and
bytecode, checking the mint event and initial balance, and executing distribution
and liquidity setup. No transaction was broadcast for this assignment and no key
or RPC configuration is included. There is no token-level maintenance or admin
handover after deployment. Holders manage their own transfers and allowances.
Tokens sent to a contract without a withdrawal mechanism can be stranded; IMD
has no privileged recovery function.

See [REVIEW.md](REVIEW.md) for validation results and review limitations.
