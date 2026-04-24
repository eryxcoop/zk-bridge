use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use serde::Serialize;

pub fn ensure_dir(path: &Path) -> Result<()> {
    fs::create_dir_all(path).with_context(|| format!("creating {}", path.display()))
}

pub fn write_pretty_json<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    fs::write(
        path,
        serde_json::to_vec_pretty(value).context("serializing JSON")?,
    )
    .with_context(|| format!("writing {}", path.display()))
}
