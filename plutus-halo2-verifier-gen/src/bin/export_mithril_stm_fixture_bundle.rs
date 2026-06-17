use anyhow::{Context, Result, anyhow, bail};
use mithril_stm::Parameters;
use plutus_halo2_verifier_gen::circuits::mithril_stm::{
    NormalizedStmBundle, generate_stm_fixture_bundle,
};
use plutus_halo2_verifier_gen::plutus_gen::mithril_stm_proof_export::{
    CertificateMetadata, CertificateProtocolMessage,
    CertificateProtocolParameters, CertificateSignatureInfo,
    InputBundle, InputCertificates, InputCertificate,
    InputCircuit, InputMerklePath, InputParameters,
    InputPhiF, InputRegistration, InputSource, InputStatement,
    InputWitness, InputWitnessEntry, SignedEntity,
};
use std::env;
use std::fs;
use std::path::PathBuf;

const DEFAULT_PARTIES: usize = 10;
const DEFAULT_MESSAGE: [u8; 32] = [7u8; 32];
const DEFAULT_SEED: [u8; 32] = [9u8; 32];

fn main() -> Result<()> {
    env_logger::init();

    let mut args = env::args().skip(1);
    let mut output = None::<PathBuf>;
    let mut nparties = DEFAULT_PARTIES;
    let mut params = Parameters {
        m: 200,
        k: 5,
        phi_f: 0.8,
    };
    let mut message = DEFAULT_MESSAGE;
    let mut seed = DEFAULT_SEED;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--output" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --output"))?;
                output = Some(PathBuf::from(value));
            }
            "--parties" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --parties"))?;
                nparties = value.parse().context("Invalid usize for --parties")?;
            }
            "--m" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --m"))?;
                params.m = value.parse().context("Invalid u64 for --m")?;
            }
            "--k" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --k"))?;
                params.k = value.parse().context("Invalid u64 for --k")?;
            }
            "--phi-f" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --phi-f"))?;
                params.phi_f = value.parse().context("Invalid f64 for --phi-f")?;
            }
            "--message" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --message"))?;
                message = parse_bytes32(&value, "--message")?;
            }
            "--seed" => {
                let value = args
                    .next()
                    .ok_or_else(|| anyhow!("Missing value for --seed"))?;
                seed = parse_bytes32(&value, "--seed")?;
            }
            "--help" | "-h" => {
                print_usage();
                return Ok(());
            }
            unknown => bail!("Unknown argument: {unknown}"),
        }
    }

    let output = output.ok_or_else(|| anyhow!("Missing required --output"))?;
    let normalized_bundle = generate_stm_fixture_bundle(params, nparties, message, seed)
        .context("Failed to generate deterministic Mithril STM fixture bundle")?;
    let bundle = input_bundle_from_normalized_bundle(&normalized_bundle);
    let serialized =
        serde_json::to_vec_pretty(&bundle).context("Failed to serialize fixture bundle")?;
    fs::write(&output, serialized)
        .with_context(|| format!("Failed to write fixture bundle to {}", output.display()))?;

    println!(
        "fixture_bundle_written output={} parties={} message={}",
        output.display(),
        nparties,
        bytes32_hex(&message)
    );
    Ok(())
}

fn input_bundle_from_normalized_bundle(bundle: &NormalizedStmBundle) -> InputBundle {
    let entries = bundle
        .witness
        .entries
        .iter()
        .map(|entry| {
            let siblings = entry
                .merkle_path
                .siblings
                .iter()
                .map(bytes32_hex)
                .collect();

            InputWitnessEntry {
                signer_index: entry.signer_index,
                lottery_index: entry.lottery_index,
                verification_key_snark: hex_bytes(&entry.verification_key_snark),
                target: bytes32_hex(&entry.target),
                merkle_path: InputMerklePath {
                    leaf_index: entry.merkle_path.leaf_index,
                    siblings,
                },
                unique_schnorr_signature: hex_bytes(&entry.unique_schnorr_signature),
            }
        })
        .collect();

    let parent = InputCertificate {
        kind: "genesis".to_string(),
        hash: bytes32_hex(&bundle.certificates.parent.hash),
        prev_hash: hex_bytes(&bundle.certificates.parent.prev_hash),
        epoch: bundle.certificates.parent.epoch,
        metadata: CertificateMetadata {
            network: "poc".to_string(),
            protocol_version: "0.1.0".to_string(),
            initiated_at: "0x00".to_string(),
            sealed_at: "0x01".to_string(),
        },
        protocol_parameters: CertificateProtocolParameters {
            k: bundle.stm_parameters.k,
            m: bundle.stm_parameters.m,
            phi_f: "0x00cccccd".to_string(),
        },
        protocol_message: CertificateProtocolMessage {
            current_epoch_text: "0".to_string(),
            next_aggregate_verification_key_text: "".to_string(),
            next_aggregate_verification_key_snark_text: "".to_string(),
            next_protocol_parameters_text: "".to_string(),
            cardano_transactions_merkle_root_hex: None,
        },
        signed_message: bytes32_hex(&bundle.certificates.parent.signed_message),
        aggregate_verification_key_text: "".to_string(),
        aggregate_verification_key_snark_text: "".to_string(),
        signature: CertificateSignatureInfo {
            signature_type: "genesis".to_string(),
            bytes_hex: "0x".to_string(),
        },
        signed_entity: SignedEntity {
            kind: "unknown".to_string(),
            epoch: None,
            block_number: None,
        },
    };
    let child = InputCertificate {
        kind: "standard".to_string(),
        hash: bytes32_hex(&bundle.certificates.child.hash),
        prev_hash: hex_bytes(&bundle.certificates.child.prev_hash),
        epoch: bundle.certificates.child.epoch,
        metadata: CertificateMetadata {
            network: "poc".to_string(),
            protocol_version: "0.1.0".to_string(),
            initiated_at: "0x02".to_string(),
            sealed_at: "0x03".to_string(),
        },
        protocol_parameters: CertificateProtocolParameters {
            k: bundle.stm_parameters.k,
            m: bundle.stm_parameters.m,
            phi_f: "0x00cccccd".to_string(),
        },
        protocol_message: CertificateProtocolMessage {
            current_epoch_text: "1".to_string(),
            next_aggregate_verification_key_text: "".to_string(),
            next_aggregate_verification_key_snark_text: "".to_string(),
            next_protocol_parameters_text: "".to_string(),
            cardano_transactions_merkle_root_hex: None,
        },
        signed_message: bytes32_hex(&bundle.certificates.child.signed_message),
        aggregate_verification_key_text: "".to_string(),
        aggregate_verification_key_snark_text: "".to_string(),
        signature: CertificateSignatureInfo {
            signature_type: "multi".to_string(),
            bytes_hex: "0x1234".to_string(),
        },
        signed_entity: SignedEntity {
            kind: "mithril_stake_distribution".to_string(),
            epoch: Some(1),
            block_number: None,
        },
    };

    InputBundle {
        schema_version: "1.0.0".to_string(),
        bundle_kind: "mithril_stm_bundle".to_string(),
        source: InputSource {
            source_id: "synthetic-test-fixture".to_string(),
            source_kind: "fixture".to_string(),
            network: "poc".to_string(),
            generated_at: None,
            notes: Some("Deterministic fixture bundle exported from the circuit runtime".to_string()),
        },
        circuit: InputCircuit {
            name: "mithril_stm".to_string(),
            public_input_contract:
                "public_input_1=registration_merkle_root,public_input_2=child_certificate.signed_message"
                    .to_string(),
        },
        stm_parameters: InputParameters {
            m: bundle.stm_parameters.m,
            k: bundle.stm_parameters.k,
            phi_f: InputPhiF::Number(bundle.stm_parameters.phi_f),
        },
        certificates: InputCertificates { parent, child },
        statement: InputStatement {
            public_input_1_merkle_root: bytes32_hex(&bundle.statement.public_input_1_merkle_root),
            public_input_2_signed_message: bytes32_hex(&bundle.statement.public_input_2_signed_message),
        },
        registration: InputRegistration {
            total_stake: bundle.registration.parties_count as u64,
            parties_count: bundle.registration.parties_count,
            merkle_tree_depth: bundle.registration.merkle_tree_depth,
        },
        witness: InputWitness { entries },
    }
}

fn hex_bytes(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

fn bytes32_hex(bytes: &[u8; 32]) -> String {
    hex_bytes(bytes)
}

fn parse_bytes32(value: &str, flag: &str) -> Result<[u8; 32]> {
    let normalized = value.strip_prefix("0x").unwrap_or(value);
    if normalized.len() != 64 {
        bail!("{flag} must be exactly 32 bytes encoded as 64 hex chars");
    }
    let bytes = hex::decode(normalized).with_context(|| format!("Invalid hex in {flag}"))?;
    bytes
        .try_into()
        .map_err(|_| anyhow!("{flag} must decode to 32 bytes"))
}

fn print_usage() {
    eprintln!(
        "Usage:
  cargo run --bin export_mithril_stm_fixture_bundle -- --output <bundle.json> [--parties <n>] [--m <m>] [--k <k>] [--phi-f <f64>] [--message <32-byte-hex>] [--seed <32-byte-hex>]"
    );
}
