//! Canonical minimal locking-transaction builder.
//!
//! Reads a JSON description of the bridge's canonical locking transaction from a
//! file (or stdin when the path is `-`) and prints `{ body_cbor_hex, tx_hash_hex }`
//! to stdout.
//!
//! The canonical layout is intentionally rigid so the on-chain Aiken validator
//! can reconstruct the exact same body bytes from redeemer fields:
//!   - body key 0 (inputs):  a set (Conway tag 258) of exactly ONE input
//!   - body key 1 (outputs): exactly ONE Babbage/Conway map output at index 0,
//!                           holding `lovelace + (policy, name, amount)` and an
//!                           inline `LockingTxDatum`
//!   - body key 2 (fee):     the fee
//!   - every other body field omitted
//!
//! The inline datum is passed through verbatim (`datum_cbor_hex`) so its exact
//! encoding is owned by a single producer (Aiken's `cbor.serialise` in tests /
//! the off-chain pipeline) and can never drift from what the validator hashes.

use std::collections::BTreeMap;
use std::fs;

use pallas::{
    codec::{
        minicbor,
        utils::{Bytes, CborWrap, KeepRaw, MaybeIndefArray, PositiveCoin, Set},
    },
    ledger::{
        primitives::{
            conway::{
                Constr, DatumOption, PlutusData, PostAlonzoTransactionOutput, TransactionBody,
                TransactionOutput, Value as ConwayValue,
            },
            BoundedBytes, Hash, TransactionInput,
        },
        traverse::ComputeHash,
    },
};
use serde::{Deserialize, Serialize};

/// Plutus `Constr 0` tag, matching Aiken's `cbor.serialise` of a record /
/// first-constructor enum variant.
const CONSTR_0_TAG: u64 = 121;

#[derive(Deserialize)]
struct LockingTxSpec {
    /// 32-byte hex of the funding UTxO transaction id consumed by the locking tx.
    input_tx_id_hex: String,
    /// Output index of the funding UTxO.
    input_index: u64,
    /// Raw Cardano address bytes (hex) of the bridge lock output.
    output_address_hex: String,
    /// Lovelace (min-ada) in the lock output.
    output_lovelace: u64,
    /// 28-byte hex policy id of the bridged native asset.
    asset_policy_id_hex: String,
    /// Hex of the bridged native asset name.
    asset_name_hex: String,
    /// Quantity of the bridged native asset locked (must be > 0).
    asset_amount: u64,
    /// Inline `LockingTxDatum` already serialised to PlutusData CBOR (hex).
    /// When omitted, the datum is built from `bridge_id_hex` + `destination_vkh_hex`.
    #[serde(default)]
    datum_cbor_hex: Option<String>,
    /// 28-byte hex `BridgeId` (policy id) stored in the inline `LockingTxDatum`.
    #[serde(default)]
    bridge_id_hex: Option<String>,
    /// 28-byte hex verification-key hash of the destination (built as a
    /// `VerificationKey` payment credential inside the `LockingTxDatum`).
    #[serde(default)]
    destination_vkh_hex: Option<String>,
    /// Transaction fee.
    fee: u64,
}

#[derive(Serialize)]
struct LockingTxOut {
    body_cbor_hex: String,
    tx_hash_hex: String,
    datum_cbor_hex: String,
}

/// Builds the inline `LockingTxDatum` PlutusData CBOR from its fields, matching
/// what Aiken's `cbor.serialise` produces on-chain:
///   Constr 0 [ bridge_id, Constr 0 [ destination_vkh ] ]
/// (`destination_address` is a `VerificationKey` payment credential).
fn build_datum_cbor(bridge_id: Vec<u8>, destination_vkh: Vec<u8>) -> Result<Vec<u8>, String> {
    let destination = PlutusData::Constr(Constr {
        tag: CONSTR_0_TAG,
        any_constructor: None,
        fields: MaybeIndefArray::Indef(vec![PlutusData::BoundedBytes(BoundedBytes::from(
            destination_vkh,
        ))]),
    });
    let datum = PlutusData::Constr(Constr {
        tag: CONSTR_0_TAG,
        any_constructor: None,
        fields: MaybeIndefArray::Indef(vec![
            PlutusData::BoundedBytes(BoundedBytes::from(bridge_id)),
            destination,
        ]),
    });
    minicbor::to_vec(&datum).map_err(|e| format!("encode datum: {e}"))
}

fn decode_hex(label: &str, value: &str) -> Result<Vec<u8>, String> {
    hex::decode(value.trim_start_matches("0x")).map_err(|e| format!("decode {label}: {e}"))
}

fn fixed_hash<const N: usize>(label: &str, bytes: Vec<u8>) -> Result<Hash<N>, String> {
    let arr: [u8; N] = bytes
        .try_into()
        .map_err(|_| format!("{label} must be {N} bytes"))?;
    Ok(Hash::from(arr))
}

fn build(spec: &LockingTxSpec) -> Result<LockingTxOut, String> {
    // --- input set (body key 0) ---
    let input_tx_id: Hash<32> =
        fixed_hash("input_tx_id_hex", decode_hex("input_tx_id_hex", &spec.input_tx_id_hex)?)?;
    let inputs: Set<TransactionInput> = Set::from(vec![TransactionInput {
        transaction_id: input_tx_id,
        index: spec.input_index,
    }]);

    // --- output value (lovelace + single native asset) ---
    let policy: Hash<28> = fixed_hash(
        "asset_policy_id_hex",
        decode_hex("asset_policy_id_hex", &spec.asset_policy_id_hex)?,
    )?;
    let asset_name: Bytes = Bytes::from(decode_hex("asset_name_hex", &spec.asset_name_hex)?);
    let amount = PositiveCoin::try_from(spec.asset_amount)
        .map_err(|_| "asset_amount must be > 0".to_string())?;

    let mut by_name: BTreeMap<Bytes, PositiveCoin> = BTreeMap::new();
    by_name.insert(asset_name, amount);
    let mut multiasset: BTreeMap<Hash<28>, BTreeMap<Bytes, PositiveCoin>> = BTreeMap::new();
    multiasset.insert(policy, by_name);
    let value = ConwayValue::Multiasset(spec.output_lovelace, multiasset);

    // --- inline datum: either passed through verbatim, or built from fields ---
    let datum_bytes = match &spec.datum_cbor_hex {
        Some(hex) => decode_hex("datum_cbor_hex", hex)?,
        None => {
            let bridge_id = decode_hex(
                "bridge_id_hex",
                spec.bridge_id_hex
                    .as_deref()
                    .ok_or("either datum_cbor_hex or bridge_id_hex is required")?,
            )?;
            let destination_vkh = decode_hex(
                "destination_vkh_hex",
                spec.destination_vkh_hex
                    .as_deref()
                    .ok_or("either datum_cbor_hex or destination_vkh_hex is required")?,
            )?;
            build_datum_cbor(bridge_id, destination_vkh)?
        }
    };
    let datum: KeepRaw<PlutusData> =
        minicbor::decode(&datum_bytes).map_err(|e| format!("decode datum cbor: {e}"))?;

    // --- output (body key 1) ---
    let output = PostAlonzoTransactionOutput {
        address: Bytes::from(decode_hex("output_address_hex", &spec.output_address_hex)?),
        value,
        datum_option: Some(KeepRaw::from(DatumOption::Data(CborWrap(datum)))),
        script_ref: None,
    };

    let body = TransactionBody {
        inputs,
        outputs: vec![TransactionOutput::PostAlonzo(KeepRaw::from(output))],
        fee: spec.fee,
        ttl: None,
        certificates: None,
        withdrawals: None,
        auxiliary_data_hash: None,
        validity_interval_start: None,
        mint: None,
        script_data_hash: None,
        collateral: None,
        required_signers: None,
        network_id: None,
        collateral_return: None,
        total_collateral: None,
        reference_inputs: None,
        voting_procedures: None,
        proposal_procedures: None,
        treasury_value: None,
        donation: None,
    };

    let body_cbor = minicbor::to_vec(&body).map_err(|e| format!("encode tx body: {e}"))?;
    let tx_hash = body.compute_hash();

    Ok(LockingTxOut {
        body_cbor_hex: hex::encode(body_cbor),
        tx_hash_hex: hex::encode(tx_hash),
        datum_cbor_hex: hex::encode(datum_bytes),
    })
}

fn main() -> Result<(), String> {
    let path = std::env::args()
        .nth(1)
        .ok_or_else(|| "usage: build_canonical_locking_tx <spec.json | ->".to_string())?;

    let raw = if path == "-" {
        use std::io::Read;
        let mut buf = String::new();
        std::io::stdin()
            .read_to_string(&mut buf)
            .map_err(|e| format!("read stdin: {e}"))?;
        buf
    } else {
        fs::read_to_string(&path).map_err(|e| format!("read {path}: {e}"))?
    };

    let spec: LockingTxSpec =
        serde_json::from_str(&raw).map_err(|e| format!("parse spec json: {e}"))?;
    let out = build(&spec)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&out).map_err(|e| format!("encode out json: {e}"))?
    );
    Ok(())
}
