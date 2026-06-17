use aiken/cbor.{serialise}
use cardano/address.{PaymentCredential, Script, VerificationKey}
use cardano/transaction.{Datum, DatumHash, InlineDatum, NoDatum}

pub fn payment_credential_bytes(
  payment_credential: PaymentCredential,
) -> ByteArray {
  when payment_credential is {
    VerificationKey(hash) -> hash
    Script(hash) -> hash
  }
}

pub fn datum_bytes(datum: Datum) -> ByteArray {
  when datum is {
    NoDatum -> #""
    InlineDatum(data) -> serialise(data)
    DatumHash(hash) -> hash
  }
}
