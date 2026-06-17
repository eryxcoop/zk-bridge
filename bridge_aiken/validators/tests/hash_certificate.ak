use aiken/crypto.{sha2_256, sha3_256}
use certificate_metadata.{
  ProtocolParameters, hash_certificate_metadata, hash_protocol_parameters,
}
use mithril_certificate.{MithrilCertificate, hash_certificate}
use protocol_message.{
  CardanoDatabaseMerkleRoot, CardanoStakeDistributionEpoch,
  CardanoStakeDistributionMerkleRoot, CardanoTransactionsMerkleRoot,
  LatestBlockNumber, NextAggregateVerificationKey, NextProtocolParameters,
  ProtocolMessage, SnapshotDigest, hash_protocol_message,
}
use tests/helpers/certificates.{
  genesis_certificate_for_hash_test, mock_certificate_metadata,
  parent_of_simple_cardano_transactions_certificate,
  simple_cardano_transactions_certificate, simple_genesis_certificate,
  simple_sd_certificate, standard_certificate_for_hash_test,
}

test sha2_256_test() {
  let input: ByteArray =
    #"00a5e9ef826387c595d2e7cff950cf0a995546afc67d3c3ca8583e2c11496605"
  sha2_256(input) == #"939eeb1a5700fc19aca7d3fef5d9644e47914ed1a915a53d6e397c3dc0d34272"
}

test sha3_256_test() {
  let input: ByteArray = "holaquetal1234"
  sha3_256(input) == #"77f8a14b80d6a1dc6e1fc70e38b59dd7e148a1ea3ee78156a011fb6756e88d2a"
}

test hash_certificate_test() {
  let certificate: MithrilCertificate = standard_certificate_for_hash_test()
  certificate.hash == hash_certificate(certificate)
}

test hash_genesis_certificate_test() {
  let certificate: MithrilCertificate = genesis_certificate_for_hash_test()
  certificate.hash == hash_certificate(certificate)
}

test hash_real_genesis_certificate_test() {
  let certificate: MithrilCertificate = simple_genesis_certificate()
  certificate.hash == hash_certificate(certificate)
}

test hash_real_sd_certificate_test() {
  let certificate: MithrilCertificate = simple_sd_certificate()
  certificate.hash == hash_certificate(certificate)
}

test hash_real_cardano_transactions_certificate_test() {
  let certificate: MithrilCertificate =
    simple_cardano_transactions_certificate()
  certificate.hash == hash_certificate(certificate)
}

test hash_parent_of_real_cardano_transactions_certificate_test() {
  let certificate: MithrilCertificate =
    parent_of_simple_cardano_transactions_certificate()
  certificate.hash == hash_certificate(certificate)
}

test hash_certificate_metadata_test() {
  let metadata = mock_certificate_metadata()
  let expected_result =
    #"053571e34d17caf9ed8e42858593cf5a323395439251578db497a4e1b6521f80"
  expected_result == hash_certificate_metadata(metadata)
}

test hash_protocol_parameters_test() {
  let protocol_parameters =
    ProtocolParameters { k: 1000, m: 100, phi_f: #"001f7cee" }
  let expected_result =
    #"ace019657cd995b0dfbb1ce8721a1092715972c4ae0171cc636ab4a44e6e4279"
  expected_result == hash_protocol_parameters(protocol_parameters)
}

test hash_protocol_message_test() {
  let protocol_message: ProtocolMessage =
    [
      Pair(SnapshotDigest, @"snapshot-digest-123"),
      Pair(CardanoTransactionsMerkleRoot, @"ctx-merkle-root-123"),
      Pair(NextAggregateVerificationKey, @"next-avk-123"),
      Pair(NextProtocolParameters, @"next-protocol-parameters-123"),
      Pair(LatestBlockNumber, @"latest-immutable-file-number-123"),
      Pair(
        CardanoStakeDistributionEpoch,
        @"cardano-stake-distribution-epoch-123",
      ),
      Pair(
        CardanoStakeDistributionMerkleRoot,
        @"cardano-stake-distribution-merkle-root-123",
      ), Pair(CardanoDatabaseMerkleRoot, @"cardano-database-merkle-root-123"),
    ]

  let expected_result =
    #"661f56d9c2b763bdc0ddc18566c301e4a24f96e5d1e4e29a3af8809bf1f43028"
  expected_result == hash_protocol_message(protocol_message)
}

test hash_protocol_message_2_test() {
  let protocol_message =
    [
      Pair(SnapshotDigest, @"snapshot-digest-123"),
      Pair(
        NextAggregateVerificationKey,
        @"7b226d745f636f6d6d69746d656e74223a7b22726f6f74223a5b37332c37342c3232392c3235302c3132322c3232362c38392c33372c3233312c3234352c3130362c3138332c3132372c332c39392c3137372c3231372c36352c3135322c3133352c33322c36372c3232332c33352c3134312c35312c342c3132352c3230332c33382c3139362c3231325d2c226e725f6c6561766573223a32342c22686173686572223a6e756c6c7d2c22746f74616c5f7374616b65223a35323337353137363336353838327d",
      ),
    ]
  let expected_result =
    #"82c7e6a3a8668ffee721af0ad4ea159ed6ac3792a2c58d890f740a349134db4a"
  expected_result == hash_protocol_message(protocol_message)
}
