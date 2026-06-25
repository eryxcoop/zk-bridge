use aiken/builtin.{blake2b_256}
use aiken/primitive/bytearray

/// Canonical reconstruction of the bridge's *minimal locking transaction* body,
/// so the on-chain validator can recompute the real Cardano transaction id
/// (`blake2b_256` of the canonical Conway tx-body CBOR) from redeemer fields and
/// match it against the hash the Mithril snapshot proof binds.
///
/// The locking transaction is forced to a rigid layout (one input, one output at
/// index 0 holding the bridged native asset plus an inline `LockingTxDatum`, a
/// fee, and nothing else). Under that constraint the body bytes are fully
/// determined by a handful of fields, so we *serialise* them here rather than
/// parsing an opaque transaction.
///
/// The byte layout is kept byte-for-byte identical to what `pallas` emits for
/// the same body in `tools/build_canonical_locking_tx` (the off-chain single
/// source of truth); a cross-check test asserts both hashes agree.
/// Minimal CBOR unsigned integer (major type 0).
fn cbor_uint(n: Int) -> ByteArray {
  if n < 24 {
    bytearray.push(#"", n)
  } else if n < 256 {
    bytearray.push(bytearray.push(#"", n), 0x18)
  } else if n < 65536 {
    bytearray.concat(#"19", bytearray.from_int_big_endian(n, 2))
  } else if n < 4294967296 {
    bytearray.concat(#"1a", bytearray.from_int_big_endian(n, 4))
  } else {
    bytearray.concat(#"1b", bytearray.from_int_big_endian(n, 8))
  }
}

/// Minimal CBOR byte string (major type 2): length header followed by `b`.
fn cbor_bytes(b: ByteArray) -> ByteArray {
  let len = bytearray.length(b)
  let header =
    if len < 24 {
      bytearray.push(#"", 0x40 + len)
    } else if len < 256 {
      bytearray.push(bytearray.push(#"", len), 0x58)
    } else if len < 65536 {
      bytearray.concat(#"59", bytearray.from_int_big_endian(len, 2))
    } else {
      bytearray.concat(#"5a", bytearray.from_int_big_endian(len, 4))
    }
  bytearray.concat(header, b)
}

/// Rebuilds the canonical Conway tx-body CBOR of the minimal locking
/// transaction.
///
/// - `input_tx_id` / `input_index`: the single spent input.
/// - `output_address`: raw Cardano address bytes of the bridge lock output.
/// - `output_lovelace`: min-ada carried by the lock output.
/// - `asset_policy_id` / `asset_name` / `asset_amount`: the bridged native asset.
/// - `datum`: the inline `LockingTxDatum` already serialised to PlutusData CBOR
///   (e.g. via `aiken/cbor.serialise`).
/// - `fee`: the transaction fee.
pub fn canonical_locking_tx_body(
  input_tx_id: ByteArray,
  input_index: Int,
  output_address: ByteArray,
  output_lovelace: Int,
  asset_policy_id: ByteArray,
  asset_name: ByteArray,
  asset_amount: Int,
  datum: ByteArray,
  fee: Int,
) -> ByteArray {
  // body key 0: inputs as a set (Conway tag 258) of exactly one input
  let inputs_set =
    #"d90102"
      |> bytearray.concat(#"81")
      |> bytearray.concat(#"82")
      |> bytearray.concat(cbor_bytes(input_tx_id))
      |> bytearray.concat(cbor_uint(input_index))

  // output value: [lovelace, { policy: { name: amount } }]
  let value =
    #"82"
      |> bytearray.concat(cbor_uint(output_lovelace))
      |> bytearray.concat(#"a1")
      |> bytearray.concat(cbor_bytes(asset_policy_id))
      |> bytearray.concat(#"a1")
      |> bytearray.concat(cbor_bytes(asset_name))
      |> bytearray.concat(cbor_uint(asset_amount))

  // inline datum option: [1, 24(<datum cbor>)]
  let datum_option =
    #"82"
      |> bytearray.concat(#"01")
      |> bytearray.concat(#"d818")
      |> bytearray.concat(cbor_bytes(datum))

  // body key 1: outputs, a single Babbage/Conway map output at index 0
  let output_map =
    #"a3"
      |> bytearray.concat(#"00")
      |> bytearray.concat(cbor_bytes(output_address))
      |> bytearray.concat(#"01")
      |> bytearray.concat(value)
      |> bytearray.concat(#"02")
      |> bytearray.concat(datum_option)

  // tx body: { 0: inputs, 1: [output], 2: fee }
  #"a3"
    |> bytearray.concat(#"00")
    |> bytearray.concat(inputs_set)
    |> bytearray.concat(#"01")
    |> bytearray.concat(#"81")
    |> bytearray.concat(output_map)
    |> bytearray.concat(#"02")
    |> bytearray.concat(cbor_uint(fee))
}

/// Canonical Cardano transaction id of the minimal locking transaction:
/// `blake2b_256` of the reconstructed body.
pub fn canonical_locking_tx_hash(
  input_tx_id: ByteArray,
  input_index: Int,
  output_address: ByteArray,
  output_lovelace: Int,
  asset_policy_id: ByteArray,
  asset_name: ByteArray,
  asset_amount: Int,
  datum: ByteArray,
  fee: Int,
) -> ByteArray {
  blake2b_256(
    canonical_locking_tx_body(
      input_tx_id,
      input_index,
      output_address,
      output_lovelace,
      asset_policy_id,
      asset_name,
      asset_amount,
      datum,
      fee,
    ),
  )
}
