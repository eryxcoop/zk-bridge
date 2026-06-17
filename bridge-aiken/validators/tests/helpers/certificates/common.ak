use aiken/primitive/string
use mithril/certificate_metadata.{
  CertificateMetadata, ProtocolParameters, ProtocolVersion,
  StakeDistributionParty,
}
use mithril/mithril_certificate.{MithrilCertificate}
use mithril/protocol_message.{
  CurrentEpoch, NextAggregateVerificationKey, NextProtocolParameters,
  NextSnarkAggregateVerificationKey, ProtocolMessage, SnapshotDigest,
}

pub fn certificate_metadata_for_new_certificate(
  parent_certificate: MithrilCertificate,
) {
  CertificateMetadata {
    network: parent_certificate.metadata.network,
    protocol_version: parent_certificate.metadata.protocol_version,
    protocol_parameters: parent_certificate.metadata.protocol_parameters,
    initiated_at: parent_certificate.metadata.initiated_at,
    sealed_at: parent_certificate.metadata.sealed_at,
    signers: [
      StakeDistributionParty { party_id: "1", stake: 10 },
      StakeDistributionParty { party_id: "2", stake: 20 },
    ],
  }
}

pub fn mock_certificate_metadata() -> CertificateMetadata {
  CertificateMetadata {
    network: "testnet",
    protocol_version: ProtocolVersion("0.1.0"),
    protocol_parameters: ProtocolParameters {
      k: 1000,
      m: 100,
      phi_f: #"001f7cee",
    },
    initiated_at: #"17b31fabeef2bdac",
    sealed_at: #"17b31fc33769a5ac",
    signers: [
      StakeDistributionParty { party_id: "1", stake: 10 },
      StakeDistributionParty { party_id: "2", stake: 20 },
    ],
  }
}

pub fn snark_avk_for_epoch(epoch: Int) -> ByteArray {
  when epoch is {
    10 -> "snark-avk-10"
    1129 -> "snark-avk-1129"
    1130 -> "snark-avk-1130"
    1149 -> "snark-avk-1149"
    1150 -> "snark-avk-1150"
    10000 -> "snark-avk-10000"
    _ -> "snark-avk-default"
  }
}

pub fn next_snark_avk_for_epoch(epoch: Int) -> String {
  when epoch is {
    10 -> @"snark-avk-11"
    1129 -> @"snark-avk-1130"
    1130 -> @"snark-avk-1131"
    1149 -> @"snark-avk-1150"
    1150 -> @"snark-avk-1151"
    10000 -> @"snark-avk-10001"
    _ -> @"snark-avk-default-next"
  }
}

pub fn mock_protocol_message(epoch: Int) -> ProtocolMessage {
  [
    Pair(SnapshotDigest, @"snapshot-digest-123"),
    Pair(
      NextAggregateVerificationKey,
      @"7b226d745f636f6d6d69746d656e74223a7b22726f6f74223a5b37332c37342c3232392c3235302c3132322c3232362c38392c33372c3233312c3234352c3130362c3138332c3132372c332c39392c3137372c3231372c36352c3135322c3133352c33322c36372c3232332c33352c3134312c35312c342c3132352c3230332c33382c3139362c3231325d2c226e725f6c6561766573223a32342c22686173686572223a6e756c6c7d2c22746f74616c5f7374616b65223a35323337353137363336353838327d",
    ),
    Pair(NextSnarkAggregateVerificationKey, next_snark_avk_for_epoch(epoch)),
    Pair(
      NextProtocolParameters,
      @"b01de82ca7e57c1bf2a56381ce265f378aeea5f1dde7f824b5ba42125c4adad2",
    ),
    Pair(CurrentEpoch, string.from_int(epoch)),
  ]
}
