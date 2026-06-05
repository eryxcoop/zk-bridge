# Third-party licenses — `vendor/`

The `.circom` files in this directory are **vendored copies of third-party code**.
They are not part of the zk-bridge project's own source (which is licensed under
LGPL-3.0) and retain the license of their respective upstream projects. All of
these licenses are compatible with LGPL-3.0.

| File(s) | Upstream project | Copyright | License | Text |
|---|---|---|---|---|
| `bitify.circom`, `binsum.circom`, `circomlib_sha256/*` | [iden3/circomlib](https://github.com/iden3/circomlib) | 0KIMS association | LGPL-3.0 | [`LICENSE-circomlib`](./LICENSE-circomlib) |
| `blake2s.circom`, `blake2_common.circom` | [bkomuves/hash-circuits](https://github.com/bkomuves/hash-circuits) | (c) 2023-2025 Faulhorn Zrt. | MIT | [`LICENSE-blake2-MIT`](./LICENSE-blake2-MIT) |
| `poseidon255.circom`, `poseidon255_constants.circom` | [jmagan/poseidon-bls12381-circom](https://github.com/jmagan/poseidon-bls12381-circom) | (c) 2024 Juan Salvador Magán Valero | MIT | [`LICENSE-poseidon255-MIT`](./LICENSE-poseidon255-MIT) |

## Notes

- The circomlib files carry the original GNU GPL header from upstream. circomlib
  as a project is distributed under LGPL-3.0; the per-file headers reference the
  GPL, which is an upstream inconsistency in circomlib itself.
- The MIT-licensed files (blake2, poseidon255) require that the copyright notice
  and the permission notice above be preserved in distribution; that is the
  purpose of this file and the accompanying `LICENSE-*` texts.
