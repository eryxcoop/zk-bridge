use ak_381/groth16.{Proof}
use stake_distribution.{StakeDistributionAssetRedeemer}
use tests/helpers/certificates.{
  simple_genesis_certificate, simple_sd_certificate,
  standard_sd_certificate_with_incorrect_aggregate_verification_key,
  standard_sd_certificate_with_incorrect_epoch_chaining,
  standard_sd_certificate_with_incorrect_parent_hash,
  standard_sd_certificate_with_incorrect_protocol_parameters,
  standard_sd_certificate_with_incorrect_signed_entity_type,
}

pub fn simple_sd_asset_redeemer() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: simple_sd_certificate(),
    proof: a_valid_mithril_certificate_proof(),
  }
}

pub fn simple_sd_asset_redeemer_for_genesis_certificate() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: simple_genesis_certificate(),
    proof: a_valid_mithril_certificate_proof(),
  }
}

pub fn sd_asset_redeemer_with_invalid_mithril_proof() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: simple_sd_certificate(),
    proof: an_invalid_mithril_certificate_proof(),
  }
}

pub fn sd_asset_redeemer_with_incorrect_parent_hash() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: standard_sd_certificate_with_incorrect_parent_hash(),
    proof: a_valid_mithril_certificate_proof(),
  }
}

pub fn sd_asset_redeemer_with_incorrect_epoch_chaining() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: standard_sd_certificate_with_incorrect_epoch_chaining(),
    proof: a_valid_mithril_certificate_proof(),
  }
}

pub fn sd_asset_redeemer_with_incorrect_aggregate_verification_key() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: standard_sd_certificate_with_incorrect_aggregate_verification_key(),
    proof: a_valid_mithril_certificate_proof(),
  }
}

pub fn sd_asset_redeemer_with_incorrect_protocol_parameters() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: standard_sd_certificate_with_incorrect_protocol_parameters(),
    proof: a_valid_mithril_certificate_proof(),
  }
}

pub fn sd_asset_redeemer_with_incorrect_signed_entity_type() -> StakeDistributionAssetRedeemer {
  StakeDistributionAssetRedeemer {
    new_certificate: standard_sd_certificate_with_incorrect_signed_entity_type(),
    proof: a_valid_mithril_certificate_proof(),
  }
}

fn a_valid_mithril_certificate_proof() {
  Proof {
    piA: #"8f24f2c09798df276236295608a009b7c86a63ce28220ccbf9fb3e00871a70be057ff583c74d24a47a02654ad1802de5",
    piB: #"b11880dfe2b2d5dd9aae12be311192eee74a3b79a9053d89cbf7ac0e8cbdfb7a58840636579da3b9bcbe68039996d50e04713884f8835f4a8ea5b7ffa67682beecd6a4807058527971034a5c7199f765d9bb8a22e140fcedb525baffb1b95102",
    piC: #"8920fbc8919dbaeb00878cb3447eb1e441760a081a50eb0f60545744153744d1e403351704f2bedee4f78fc4f28eb8e0",
  }
}

fn an_invalid_mithril_certificate_proof() {
  Proof {
    piA: #"fffffff09798df276236295608a009b7c86a63ce28220ccbf9fb3e00871a70be057ff583c74d24a47a02654ad1802de5",
    piB: #"ffffffffe2b2d5dd9aae12be311192eee74a3b79a9053d89cbf7ac0e8cbdfb7a58840636579da3b9bcbe68039996d50e04713884f8835f4a8ea5b7ffa67682beecd6a4807058527971034a5c7199f765d9bb8a22e140fcedb525baffb1b95102",
    piC: #"fffffff8919dbaeb00878cb3447eb1e441760a081a50eb0f60545744153744d1e403351704f2bedee4f78fc4f28eb8e0",
  }
}
