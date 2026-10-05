# IMD test coverage

The original `IMD.t.sol` and `Deploy.t.sol` retain the metadata, constructor mint,
factory recipient, events, launch transfer accounting, deployment restrictions,
and absence of privileged token controls checks.

`IMD.adversarial.t.sol` adds failure and boundary cases for self-transfers,
exhausted and revoked approvals, zero addresses, maximum amounts, and the finite
`uint256.max - 1` allowance boundary. Six fuzz properties cover exact round trips,
approval replacement and isolation, zero delegated transfers, cumulative spending,
self-transfer overdraws, and retrying an approved spend after a balance refill.
These properties run 1,000 cases each by default; zero, one minor unit, the whole
supply, and maximum integer values also have deterministic tests.

`IMD.invariant.t.sol` extends the existing three-actor handler with an independent
ledger initialized from the specified 1,000,000,000 * 10^18 supply. The ledger only
changes for authorized transfers and approvals, never by copying token getters.
The invariant runner interleaves ten actions, including revocations, infinite
approvals, and expected failures, for 256 sequences of 128 calls per invariant:

- The fixed supply equals the sum of all reachable holder balances.
- Every holder's balance matches authorized movements, including self-transfers.
- Every owner/spender allowance matches grants and successful spending, including
  rollback after a rejected transfer.

Rejected operations must revert with the expected error; unexpected handler
reverts fail the campaign. A deterministic handler walk verifies that nonzero
transfers and finite/infinite approval use remain reachable alongside failures.
Input bounds avoid discarding generated cases. The conservation, transition,
round-trip, and edge-case selection follow the supplied Pashov fizz and Trail of
Bits property-testing references; the test code is written for this repository.

Run offline using the existing vendored dependencies and pinned compiler:

```sh
forge build --offline
forge test --offline
forge test --offline --fuzz-seed 0x1badb002 --fuzz-runs 2048
forge fmt --check
```

For temporary outputs confined to scratch space, add
`--out test/scratch/out --cache-path test/scratch/cache` to build/test commands.
The submitted tests do not import or depend on scratch files, the supplied
protected harness, RPCs, forks, FFI, or environment mutation. The network's
protected PoolManager launch integration requires its own contracts and deployment
inputs; these tests exercise token behavior locally and do not claim to execute
that external integration harness.
