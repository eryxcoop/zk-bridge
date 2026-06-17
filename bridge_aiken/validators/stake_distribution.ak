use aiken/collection/list
use ak_381/groth16.{Proof}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
use certificate_signature.{
  GenesisSignature, MithrilStakeDistribution, MultiSignature,
}
use env
use mithril_certificate.{MithrilCertificate}
use verify_certificate.{
  verify_mithril_genesis_certificate, verify_mithril_standard_certificate,
}

pub type StakeDistributionAssetRedeemer {
  new_certificate: MithrilCertificate,
  proof: Proof,
}

pub type StakeDistributionAssetDatum {
  certificate: MithrilCertificate,
}
/// Verifies that a `MithrilCertificate` is a stake distribution certificate. This is implied
/// by its signed entity. Besides, the epoch of its signed entity must match its epoch.
fn is_stake_distribution_certificate(certificate: MithrilCertificate) -> Bool {
  expect MultiSignature { signed_entity_type, .. } = certificate.signature
  expect MithrilStakeDistribution { epoch } = signed_entity_type
  (epoch == certificate.epoch)?
}

fn find_new_certificate_output(tx: Transaction, new_certificate: MithrilCertificate) -> Option<Output> {
  list.find(
    tx.outputs,
    fn(o) {
      when o.datum is {
        InlineDatum(raw) ->
          if raw is StakeDistributionAssetDatum { certificate }: StakeDistributionAssetDatum {
            (certificate == new_certificate)?
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

validator stake_distribution_validator_spend {
  spend(
    datum: Option<StakeDistributionAssetDatum>,
    redeemer: StakeDistributionAssetRedeemer,
    own_ref: OutputReference,
    tx: Transaction,
  ) { 
    // We verify the parent certificate from the input's datum
    expect Some(StakeDistributionAssetDatum {
      certificate: parent_certificate,
    }) = datum

    // We verify that the stake distribution NFT is being transferred from the UTxO with the parent certificate
    // to the UTxO with the new certificate. `own_input` is the parent certificate's input.
    expect Some(own_input) = transaction.find_input(tx.inputs, own_ref)

    // `redeemer` contains a genesis certificate, and the transaction generates an UTxO with
    // an NFT with that certificate as its datum.
    let StakeDistributionAssetRedeemer { new_certificate, proof } = redeemer
    expect Some(new_certificate_output) = find_new_certificate_output(tx, new_certificate)
    and {
      (new_certificate_output.address.payment_credential == own_input.output.address.payment_credential)?,
      is_stake_distribution_certificate(new_certificate)?,
      assets.has_nft_strict(
        own_input.output.value,
        env.stake_distribution_asset_policy_id,
        env.stake_distribution_asset_name,
      )?,
      assets.has_nft_strict(
        new_certificate_output.value,
        env.stake_distribution_asset_policy_id,
        env.stake_distribution_asset_name,
      )?,
      verify_mithril_standard_certificate(
        new_certificate,
        parent_certificate,
        proof,
      )?,
    }
  }

  else(_) {
    fail
  }
}

validator stake_distribution_validator_mint(unique_mint_utxo_ref: OutputReference) {
  mint(redeemer: StakeDistributionAssetRedeemer, policy_id: PolicyId, tx: Transaction) {
    // `stake_distribution_validator.mint` should only be possible to execute once
    let is_output_consumed =
      list.any(
        tx.inputs,
        fn(input) { input.output_reference == unique_mint_utxo_ref },
      )

    // `redeemer` contains a genesis certificate, and the transaction generates an UTxO with
    // an NFT with that certificate as its datum.
    let StakeDistributionAssetRedeemer { new_certificate, .. } = redeemer
    expect GenesisSignature { .. } = new_certificate.signature
    expect Some(genesis_certificate_output) = find_new_certificate_output(tx, new_certificate)

    and {
      is_output_consumed?,
      // We could also use `tx.mint` for this part
      assets.has_nft_strict(
        genesis_certificate_output.value,
        policy_id,
        env.stake_distribution_asset_name,
      )?,
      // the genesis certificate contained in `redeemer` is valid. we notice that the `GenesisVerificationKey`
      // is hardcoded in this validator
      verify_mithril_genesis_certificate(
        new_certificate,
        env.genesis_verification_key,
      )?,
    }
  }

  else(_) {
    fail
  }
}
