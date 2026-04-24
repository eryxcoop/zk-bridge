use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitKind {
    SnapshotMembership,
    TxSetUpdate,
}

#[derive(Debug, Clone)]
pub struct ProofTarget {
    pub kind: CircuitKind,
    pub crate_dir: PathBuf,
    pub exporter_bin: &'static str,
    pub output_dir_name: &'static str,
}

pub fn proof_targets(repo_root: &Path) -> [ProofTarget; 2] {
    [
        ProofTarget {
            kind: CircuitKind::SnapshotMembership,
            crate_dir: repo_root.join("circuit_transaction_snapshot"),
            exporter_bin: "arkworks_circom_fixture_export",
            output_dir_name: "snapshot_membership",
        },
        ProofTarget {
            kind: CircuitKind::TxSetUpdate,
            crate_dir: repo_root.join("circuit_inclusion_exclusion"),
            exporter_bin: "arkworks_circom_fixture_export",
            output_dir_name: "tx_set_update",
        },
    ]
}
