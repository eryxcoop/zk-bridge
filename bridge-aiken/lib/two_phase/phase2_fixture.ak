use two_phase/two_phase_types.{Phase1State, Phase2State, ReducedRedeemer}

pub const valid_phase1_signer_vkh: ByteArray =
  #"0dd172b9b1866fd9513b96fcbe378a2d5adc7fb499949e8865d53edf"

pub const valid_reclaim_after_ms: Int = 1_700_000_000_000

pub const valid_statement_hash: ByteArray =
  #"27a7a6e528a0bd083f05142b14add9885667f6783ab0daf3fb9bf50e60a14d55"

pub const valid_locked_lovelace: Int = 3_000_000

pub const valid_receipt_lovelace: Int = 3_000_000

pub const valid_state: Phase1State =
  Phase1State {
    rhs_prefix: #"aca74856a6da5d027f6045d6866b202d3121564691523fa0a1bc86bab92c33d63feec81a38ae6f4110c01abba1b4fcba",
    reduced_hash: #"6a0d9996dfdb8f1ee537964cdf8071a61eee6922fd4e3fe2e24fb5a923b37f70",
    x1: #"a89e9bdef620d04eabd343899dfe283d2060511abbab1bd63405bcbc405fc505",
    x3: #"0bfe2a52b6db52dc622188522d32ad360af235fa294eac85f794ff83698a1650",
    x4: #"8f774fc65190480f152c076c6ecbf22a6f838f12c71e6d179231592114d9590a",
    v: #"96e249bdca976b4ed3a83cff5e5e4d9b843a476f8432b8c20c404d1d60e4d461",
  }

pub const valid_reduced_redeemer: ReducedRedeemer =
  ReducedRedeemer {
    vanishing_g: #"8060ee76c443c8d459e36963de4d55dadc602b3e1e4a5dc5c7ebd23f2549c6b9783fbaeb5ff37a0697e663c5f5424ee3",
    vanishing_rand: #"981bf37d7d6568b39f02e49cd753aa3a7d4891da34c60fc73e01a4437859b1818361359cc14728f751eb7d8f64b7939a",
    a1: #"a9d8717f072ae2676cc1723fe5ea09be4229b6ea5e8571afc3db411983d6b2e2d3793bb3f56759e1cc1f305e39aaec01",
    a2: #"98fbabde32d8addee3c92b9fdfb04069607ed6464e37539d05b89e316b41ecc3a7184ca41111da58c1d298c160e18cc3",
    a3: #"a5537fae86547851eacf0d3d7b8b1d82d18b641de7f5c09b284585f5d90c6e1ed5c7061616086e03e9d60611ea41b9bd",
    perm_d: #"92a35567d72adb943da2b5f363d0d4ff607e21bb228e1a37fe6864f9e82331fb7c94b3adf220957182c470330d5af049",
    lookup_1: #"90c19caf03f2bdc43ec669b3a4d88a38ecf40dc531f8489fba1653cc586ee3d48b10f5af28369e068e8d88e4f1912615",
    lookup_2: #"943079bfb8d114e6ceee12fbe9e53fed2c9812765a68ee62ec06d0c5e8ea883437c422d1dc04324e0e88e8628373ac75",
    perm_a: #"8390a00838f30844f2c974d7f8e9a9ddfa15690db0108c4038872b66778de71c19e3c4f0a3b2de5badbcd829ee749cca",
    perm_b: #"a3de1ed91200358dfc889d8b5f063fb3e336700a0013f366e37bdaaaaa2308fb5474bdf5953fa459e71c558c1d4ee80b",
    perm_c: #"a7fecaf48e142b618a13e9921675fd280ed2d5b99950b470cb30aff11c22bf5f96c231df6c4af2a73a90250c555a398f",
    perm_input_1: #"8b3ddd1f61978702f61f370cc387f33f39ba47f717001b401a076e3a7472cfde35b4e219cc5f441178b9e17d5bc0582b",
    perm_input_2: #"967b9384aaae4ee063b4428773e3718496ef9317c25c5f4391317b71445d96675c35eb3036b976e2563c530deca9ea0e",
    f_commitment: #"94786c56a5c7b6ccc0b482bb653bbfea5ac0462772043e9046ec88941e2c2300f242c7b2ebd662f058ebaa8839463de3",
    pi_term: #"8b84e7dcc3a2b4a04ea8ce3854e4c5e800d9be002894c3d07901db799cf9e0ed2cd05ef345f4c31ba6be16f1bbf7b608",
  }

pub fn valid_phase2_state() -> Phase2State {
  Phase2State {
    proof_state: valid_state,
    phase1_signer: valid_phase1_signer_vkh,
    reclaim_after: valid_reclaim_after_ms,
    statement_hash: valid_statement_hash,
  }
}
