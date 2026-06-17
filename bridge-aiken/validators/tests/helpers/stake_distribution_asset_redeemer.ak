use mithril/reduced_mithril_certificate.{ReducedMithrilCertificate}
use stake_distribution.{
  StakeDistributionMintRedeemer, spend_redeemer_from_certificate,
}
use tests/helpers/certificates/stake_distribution_certificates.{
  preview_dual_genesis_certificate, proof_export_compatible_sd_certificate,
  simple_dual_genesis_certificate, simple_genesis_certificate,
  simple_sd_certificate,
}
use tests/helpers/certificates/stake_distribution_negative_certificates.{
  dual_genesis_certificate_with_incorrect_ed25519_signature,
  dual_genesis_certificate_with_incorrect_signed_message,
  dual_genesis_certificate_with_incorrect_schnorr_signature,
  genesis_certificate_with_incorrect_signature,
  genesis_certificate_with_incorrect_signed_message,
  standard_sd_certificate_with_incorrect_aggregate_verification_key,
  standard_sd_certificate_with_incorrect_epoch_chaining,
  standard_sd_certificate_with_incorrect_parent_hash,
  standard_sd_certificate_with_incorrect_protocol_parameters,
  standard_sd_certificate_with_incorrect_signed_entity_type,
}
use tests/helpers/coherent_dual_genesis_fixture
use tests/helpers/jubjub_schnorr_fixture
use tests/helpers/preview_dual_genesis_fixture
use zk/jubjub_schnorr_verification.{JubjubSchnorrProof}

pub fn simple_sd_asset_redeemer() -> ReducedMithrilCertificate {
  spend_redeemer_from_certificate(simple_sd_certificate())
}

pub fn proof_export_compatible_sd_asset_redeemer() -> ReducedMithrilCertificate {
  spend_redeemer_from_certificate(proof_export_compatible_sd_certificate())
}

pub fn simple_sd_asset_redeemer_for_genesis_certificate() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: simple_genesis_certificate(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: jubjub_schnorr_fixture.final_proof(),
      verification_key_u: jubjub_schnorr_fixture.final_verification_key_u_bytes(),
      verification_key_v: jubjub_schnorr_fixture.final_verification_key_v_bytes(),
      signature_response: jubjub_schnorr_fixture.final_signature_response_bytes(),
      signature_challenge: jubjub_schnorr_fixture.final_signature_challenge_bytes(),
    },
  }
}

pub fn simple_sd_asset_redeemer_for_dual_genesis_certificate() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: simple_dual_genesis_certificate(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: coherent_dual_genesis_fixture.proof(),
      verification_key_u: coherent_dual_genesis_fixture.verification_key_u_bytes(),
      verification_key_v: coherent_dual_genesis_fixture.verification_key_v_bytes(),
      signature_response: coherent_dual_genesis_fixture.signature_response_bytes(),
      signature_challenge: coherent_dual_genesis_fixture.signature_challenge_bytes(),
    },
  }
}

pub fn preview_sd_asset_redeemer_for_dual_genesis_certificate() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: preview_dual_genesis_certificate(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: preview_dual_genesis_fixture.proof(),
      verification_key_u: preview_dual_genesis_fixture.verification_key_u_bytes(),
      verification_key_v: preview_dual_genesis_fixture.verification_key_v_bytes(),
      signature_response: preview_dual_genesis_fixture.signature_response_bytes(),
      signature_challenge: preview_dual_genesis_fixture.signature_challenge_bytes(),
    },
  }
}

pub fn sd_asset_redeemer_for_genesis_certificate_with_incorrect_signature() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: genesis_certificate_with_incorrect_signature(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: jubjub_schnorr_fixture.final_proof(),
      verification_key_u: jubjub_schnorr_fixture.final_verification_key_u_bytes(),
      verification_key_v: jubjub_schnorr_fixture.final_verification_key_v_bytes(),
      signature_response: jubjub_schnorr_fixture.final_signature_response_bytes(),
      signature_challenge: jubjub_schnorr_fixture.final_signature_challenge_bytes(),
    },
  }
}

pub fn sd_asset_redeemer_for_genesis_certificate_with_incorrect_signed_message() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: genesis_certificate_with_incorrect_signed_message(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: jubjub_schnorr_fixture.final_proof(),
      verification_key_u: jubjub_schnorr_fixture.final_verification_key_u_bytes(),
      verification_key_v: jubjub_schnorr_fixture.final_verification_key_v_bytes(),
      signature_response: jubjub_schnorr_fixture.final_signature_response_bytes(),
      signature_challenge: jubjub_schnorr_fixture.final_signature_challenge_bytes(),
    },
  }
}

pub fn sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_schnorr_signature() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: dual_genesis_certificate_with_incorrect_schnorr_signature(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: coherent_dual_genesis_fixture.proof(),
      verification_key_u: coherent_dual_genesis_fixture.verification_key_u_bytes(),
      verification_key_v: coherent_dual_genesis_fixture.verification_key_v_bytes(),
      signature_response: coherent_dual_genesis_fixture.signature_response_bytes(),
      signature_challenge: coherent_dual_genesis_fixture.signature_challenge_bytes(),
    },
  }
}

pub fn sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_signed_message() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: dual_genesis_certificate_with_incorrect_signed_message(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: coherent_dual_genesis_fixture.proof(),
      verification_key_u: coherent_dual_genesis_fixture.verification_key_u_bytes(),
      verification_key_v: coherent_dual_genesis_fixture.verification_key_v_bytes(),
      signature_response: coherent_dual_genesis_fixture.signature_response_bytes(),
      signature_challenge: coherent_dual_genesis_fixture.signature_challenge_bytes(),
    },
  }
}

pub fn sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_ed25519_signature() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: dual_genesis_certificate_with_incorrect_ed25519_signature(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: coherent_dual_genesis_fixture.proof(),
      verification_key_u: coherent_dual_genesis_fixture.verification_key_u_bytes(),
      verification_key_v: coherent_dual_genesis_fixture.verification_key_v_bytes(),
      signature_response: coherent_dual_genesis_fixture.signature_response_bytes(),
      signature_challenge: coherent_dual_genesis_fixture.signature_challenge_bytes(),
    },
  }
}

pub fn sd_asset_redeemer_for_dual_genesis_certificate_with_incorrect_public_input_challenge() -> StakeDistributionMintRedeemer {
  StakeDistributionMintRedeemer {
    new_certificate: simple_dual_genesis_certificate(),
    jubjub_schnorr_proof: JubjubSchnorrProof {
      proof: coherent_dual_genesis_fixture.proof(),
      verification_key_u: coherent_dual_genesis_fixture.verification_key_u_bytes(),
      verification_key_v: coherent_dual_genesis_fixture.verification_key_v_bytes(),
      signature_response: coherent_dual_genesis_fixture.signature_response_bytes(),
      signature_challenge: jubjub_schnorr_verification.decimal_ascii_bytes(
        coherent_dual_genesis_fixture.signature_challenge + 1,
      ),
    },
  }
}

pub fn sd_asset_redeemer_with_incorrect_parent_hash() -> ReducedMithrilCertificate {
  spend_redeemer_from_certificate(
    standard_sd_certificate_with_incorrect_parent_hash(),
  )
}

pub fn sd_asset_redeemer_with_incorrect_epoch_chaining() -> ReducedMithrilCertificate {
  spend_redeemer_from_certificate(
    standard_sd_certificate_with_incorrect_epoch_chaining(),
  )
}

pub fn sd_asset_redeemer_with_incorrect_aggregate_verification_key() -> ReducedMithrilCertificate {
  spend_redeemer_from_certificate(
    standard_sd_certificate_with_incorrect_aggregate_verification_key(),
  )
}

pub fn sd_asset_redeemer_with_incorrect_protocol_parameters() -> ReducedMithrilCertificate {
  spend_redeemer_from_certificate(
    standard_sd_certificate_with_incorrect_protocol_parameters(),
  )
}

pub fn sd_asset_redeemer_with_incorrect_signed_entity_type() -> ReducedMithrilCertificate {
  spend_redeemer_from_certificate(
    standard_sd_certificate_with_incorrect_signed_entity_type(),
  )
}
