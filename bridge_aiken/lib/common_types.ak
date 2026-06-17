use aiken/crypto.{Blake2b_224, Hash, VerificationKeyHash}
use ak_381/groth16.{Proof}
use cardano/address.{PaymentCredential}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, TransactionId}

/// We consider a sparse Merkle tree with the [Blake2b_224](https://en.wikipedia.org/wiki/BLAKE_(hash_function)#BLAKE2)
/// hash function to be appropriate for the representation of the set of transactions that were burned
/// in the destination chain. 
pub type MerkleRoot =
  Hash<Blake2b_224, ByteArray>

/// This includes the merkle root corresponding to the NFT representing the transaction set that was processed by the updater validator
pub type TxsUpdaterDatum {
  merkle_root: MerkleRoot,
}

/// Parameters:
/// - `tx_id` is an unique identifier for a transaction.
/// - `locked_assets_utxo_ref` is an `OutputReference` to the UTXO in the other chain which is being processed by the validator.
/// - `tx_set_update_proof` is a Groth16 Proof that lets us update the validator's Merkle Tree accordingly. 
pub type TxsUpdaterValidatorRedeemer {
  tx_id: TransactionId,
  locked_assets_utxo_ref: OutputReference,
  tx_set_update_proof: Proof,
}

/// Parameters:
/// - `destination_address_vk` is the `VerificationKeyHash` that the unlocked funds output will be for.
///   This parameter is needed for verifying the proof.
/// - `tx_id` is an unique identifier for the transaction that burned assets in the destination chain.
///   For the validation, it must be equal to the one included in the `Redeemer` for the `txs_updater` spending script.
/// - `transferred_amount` is the amount needed to construct the transferred value (which is of the opaque
///   type `Value`). This parameter is needed for verifying the proof.
/// - `transferred_asset_name` is the amount needed to construct the transferred value (which is of the
///   opaque type `Value`). This parameter is needed for verifying the proof.
/// - `transferred_asset_policy_id` is the amount needed to construct the transferred value (which is of
///   the opaque type `Value`). This parameter is needed for verifying the proof.
pub type BurningTxData {
  destination_address_vk: VerificationKeyHash,
  tx_id: TransactionId,
  transferred_amount: Int,
  transferred_asset_name: ByteArray,
  transferred_asset_policy_id: ByteArray,
  burning_tx_proof: Proof,
}

/// This is used in the locking transaction to identify the bridge we are using to transfer assets. It is needed
/// to avoid double unlockings. See readme in section `Locking transaction` for more details.
pub type BridgeId =
  PolicyId

/// The datum of the locking transaction. It contains the bridge id and the address where the assets should be transferred
/// in the destination chain
pub type LockingTxDatum {
  bridge_id: BridgeId,
  destination_address: PaymentCredential,
}
