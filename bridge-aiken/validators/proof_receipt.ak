use cardano/transaction.{OutputReference, Transaction}
use two_phase/two_phase_types.{ProofReceiptDatum}

validator proof_receipt_validator {
  spend(
    _datum: Option<ProofReceiptDatum>,
    _redeemer: Int,
    _own_ref: OutputReference,
    _tx: Transaction,
  ) {
    True
  }

  else(_) {
    fail
  }
}
