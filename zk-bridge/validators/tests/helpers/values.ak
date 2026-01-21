use cardano/assets.{
  AssetName, PolicyId, Value, from_asset, from_lovelace, merge,
}

/// Builds a value adding 1 ADA (each utxo needs a min_ada)
pub fn build_value_with_native_token(
  policy_id: PolicyId,
  token_name: AssetName,
  amount: Int,
) -> Value {
  merge(from_asset(policy_id, token_name, amount), from_lovelace(1000000))
}
