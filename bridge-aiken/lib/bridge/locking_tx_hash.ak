use aiken/builtin.{integer_to_bytearray}
use aiken/primitive/bytearray
use aiken/primitive/string
use cardano/assets.{PolicyId}
use env

const source_tx_id_max_bytes = 64

const output_index_ascii_max_bytes = 20

const input_payment_credential_max_bytes = 64

const input_datum_max_bytes = 128

const bridge_policy_id_max_bytes = 32

const transferred_asset_name_max_bytes = 32

const asset_amount_ascii_max_bytes = 20

const ada_amount_ascii_max_bytes = 20

const destination_payment_credential_max_bytes = 64

fn zero_pad(bytes: ByteArray, target_len: Int) -> ByteArray {
  if bytearray.length(bytes) >= target_len {
    bytes
  } else {
    zero_pad(bytearray.concat(bytes, #"00"), target_len)
  }
}

fn serialize_fixed_field(bytes: ByteArray, max_len: Int) -> ByteArray {
  if bytearray.length(bytes) > max_len {
    fail
  } else {
    integer_to_bytearray(True, 2, bytearray.length(bytes))
      |> bytearray.concat(zero_pad(bytes, max_len))
  }
}

pub fn preimage(
  locking_tx_input_output_reference_tx_id: ByteArray,
  locking_tx_input_output_reference_output_index: Int,
  locking_tx_input_payment_credential: ByteArray,
  locking_tx_input_datum: ByteArray,
  locking_tx_destination_payment_credential: ByteArray,
  locking_tx_asset_amount: Int,
  locking_tx_ada_amount: Int,
  policy_id: PolicyId,
) -> ByteArray {
  let output_index_ascii = bytearray.from_string(
    string.from_int(locking_tx_input_output_reference_output_index),
  )
  let asset_amount_ascii = bytearray.from_string(
    string.from_int(locking_tx_asset_amount),
  )
  let ada_amount_ascii = bytearray.from_string(
    string.from_int(locking_tx_ada_amount),
  )

  serialize_fixed_field(
    locking_tx_input_output_reference_tx_id,
    source_tx_id_max_bytes,
  )
    |> bytearray.concat(
        serialize_fixed_field(output_index_ascii, output_index_ascii_max_bytes),
      )
    |> bytearray.concat(
        serialize_fixed_field(
          locking_tx_input_payment_credential,
          input_payment_credential_max_bytes,
        ),
      )
    |> bytearray.concat(
        serialize_fixed_field(locking_tx_input_datum, input_datum_max_bytes),
      )
    |> bytearray.concat(
        serialize_fixed_field(policy_id, bridge_policy_id_max_bytes),
      )
    |> bytearray.concat(
        serialize_fixed_field(
          env.transferred_asset_name,
          transferred_asset_name_max_bytes,
        ),
      )
    |> bytearray.concat(
        serialize_fixed_field(asset_amount_ascii, asset_amount_ascii_max_bytes),
      )
    |> bytearray.concat(
        serialize_fixed_field(ada_amount_ascii, ada_amount_ascii_max_bytes),
      )
    |> bytearray.concat(
        serialize_fixed_field(
          locking_tx_destination_payment_credential,
          destination_payment_credential_max_bytes,
        ),
      )
    |> bytearray.concat(
        serialize_fixed_field(policy_id, bridge_policy_id_max_bytes),
      )
}
