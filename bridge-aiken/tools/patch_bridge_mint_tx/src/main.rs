use std::{fs, path::PathBuf};

use pallas::{
    codec::{
        minicbor,
        utils::{KeepRaw, NonEmptySet},
    },
    ledger::{
        primitives::{
            alonzo::{ExUnits, Value as AlonzoValue},
            conway::{
                LanguageViews, RedeemerTag, Redeemers, ScriptData, TransactionBody,
                TransactionOutput, Tx, Value as ConwayValue,
            },
            TransactionInput,
        },
        traverse::ComputeHash,
    },
};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct TxJson {
    cbor: String,
    #[serde(default, rename = "hash")]
    _hash: String,
}

#[derive(Serialize)]
struct TxJsonOut {
    cbor: String,
    hash: String,
}

#[derive(Deserialize)]
struct ConwayGenesis {
    #[serde(rename = "plutusV3CostModel")]
    plutus_v3_cost_model: Vec<i64>,
}

#[derive(Deserialize)]
struct Rational {
    numerator: u64,
    denominator: u64,
}

#[derive(Deserialize)]
struct ExecutionPrices {
    #[serde(rename = "prMem")]
    pr_mem: Rational,
    #[serde(rename = "prSteps")]
    pr_steps: Rational,
}

#[derive(Deserialize)]
struct AlonzoGenesis {
    #[serde(rename = "executionPrices")]
    execution_prices: ExecutionPrices,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct RedeemerOverrideSpec {
    tag: RedeemerTag,
    index: Option<u32>,
    new_units: ExUnits,
}

#[derive(Debug)]
struct CliSpec {
    in_json: PathBuf,
    out_json: PathBuf,
    conway_json: PathBuf,
    alonzo_json: PathBuf,
    fee_buffer: u64,
    overrides: Vec<RedeemerOverrideSpec>,
    collateral_txid: Option<String>,
    collateral_index: Option<u64>,
}

fn usage() -> String {
    "usage: patch_bridge_mint_tx <in-json> <out-json> <conway-json> <alonzo-json> <fee-buffer> --redeemer <tag:index:mem:steps> [--redeemer ...] [--collateral-txid <hex> --collateral-index <n>]\nlegacy: patch_bridge_mint_tx <in-json> <out-json> <conway-json> <alonzo-json> <mint-mem> <mint-steps> <fee-buffer> [<collateral-txid> <collateral-index>]".to_string()
}

fn ceil_mul_div(delta: u64, num: u64, den: u64) -> u64 {
    let delta = delta as u128;
    let num = num as u128;
    let den = den as u128;
    let out: u128 = ((delta * num) + den - 1) / den;
    out.try_into().expect("fee delta fits in u64")
}

fn fee_delta(old_units: ExUnits, new_units: ExUnits, prices: &ExecutionPrices) -> u64 {
    let mem_delta = new_units.mem.saturating_sub(old_units.mem);
    let steps_delta = new_units.steps.saturating_sub(old_units.steps);

    ceil_mul_div(mem_delta, prices.pr_mem.numerator, prices.pr_mem.denominator)
        + ceil_mul_div(
            steps_delta,
            prices.pr_steps.numerator,
            prices.pr_steps.denominator,
        )
}

fn adjust_output_coin(output: &mut TransactionOutput, delta_fee: u64) -> Result<(), String> {
    match output {
        TransactionOutput::Legacy(output) => match &mut output.amount {
            AlonzoValue::Coin(coin) => {
                *coin = coin
                    .checked_sub(delta_fee)
                    .ok_or_else(|| "change output coin underflow".to_string())?;
                Ok(())
            }
            AlonzoValue::Multiasset(coin, _) => {
                *coin = coin
                    .checked_sub(delta_fee)
                    .ok_or_else(|| "change output multiasset coin underflow".to_string())?;
                Ok(())
            }
        },
        TransactionOutput::PostAlonzo(output) => match &mut output.value {
            ConwayValue::Coin(coin) => {
                *coin = coin
                    .checked_sub(delta_fee)
                    .ok_or_else(|| "change output coin underflow".to_string())?;
                Ok(())
            }
            ConwayValue::Multiasset(coin, _) => {
                *coin = coin
                    .checked_sub(delta_fee)
                    .ok_or_else(|| "change output multiasset coin underflow".to_string())?;
                Ok(())
            }
        },
    }
}

fn parse_redeemer_tag(raw: &str) -> Result<RedeemerTag, String> {
    match raw.to_ascii_lowercase().as_str() {
        "spend" => Ok(RedeemerTag::Spend),
        "mint" => Ok(RedeemerTag::Mint),
        "cert" => Ok(RedeemerTag::Cert),
        "reward" => Ok(RedeemerTag::Reward),
        "vote" => Ok(RedeemerTag::Vote),
        "propose" => Ok(RedeemerTag::Propose),
        other => Err(format!("unsupported redeemer tag `{other}`")),
    }
}

fn parse_redeemer_override(raw: &str) -> Result<RedeemerOverrideSpec, String> {
    let mut parts = raw.split(':');
    let tag = parts
        .next()
        .ok_or_else(|| format!("invalid redeemer override `{raw}`"))?;
    let index: u32 = parts
        .next()
        .ok_or_else(|| format!("missing redeemer index in `{raw}`"))?
        .parse()
        .map_err(|e| format!("parse redeemer index in `{raw}`: {e}"))?;
    let mem: u64 = parts
        .next()
        .ok_or_else(|| format!("missing redeemer mem in `{raw}`"))?
        .parse()
        .map_err(|e| format!("parse redeemer mem in `{raw}`: {e}"))?;
    let steps: u64 = parts
        .next()
        .ok_or_else(|| format!("missing redeemer steps in `{raw}`"))?
        .parse()
        .map_err(|e| format!("parse redeemer steps in `{raw}`: {e}"))?;
    if parts.next().is_some() {
        return Err(format!(
            "redeemer override `{raw}` must have shape <tag:index:mem:steps>"
        ));
    }

    Ok(RedeemerOverrideSpec {
        tag: parse_redeemer_tag(tag)?,
        index: Some(index),
        new_units: ExUnits { mem, steps },
    })
}

fn parse_u64_arg(raw: String, name: &str) -> Result<u64, String> {
    raw.parse().map_err(|e| format!("parse {name}: {e}"))
}

fn parse_cli_spec() -> Result<CliSpec, String> {
    let raw_args: Vec<String> = std::env::args().skip(1).collect();
    if raw_args.len() < 7 {
        return Err(usage());
    }

    let in_json = PathBuf::from(raw_args[0].clone());
    let out_json = PathBuf::from(raw_args[1].clone());
    let conway_json = PathBuf::from(raw_args[2].clone());
    let alonzo_json = PathBuf::from(raw_args[3].clone());

    let maybe_new_fee_buffer = &raw_args[4];
    if maybe_new_fee_buffer.starts_with("--") {
        return Err(usage());
    }

    let legacy_mode = !raw_args[5].starts_with("--");
    if legacy_mode {
        let mint_mem = parse_u64_arg(raw_args[4].clone(), "mint-mem")?;
        let mint_steps = parse_u64_arg(raw_args[5].clone(), "mint-steps")?;
        let fee_buffer = parse_u64_arg(raw_args[6].clone(), "fee-buffer")?;
        let collateral_txid = raw_args.get(7).cloned();
        let collateral_index = raw_args
            .get(8)
            .map(|value| parse_u64_arg(value.clone(), "collateral-index"))
            .transpose()?;
        if raw_args.len() != 7 && raw_args.len() != 9 {
            return Err(usage());
        }

        return Ok(CliSpec {
            in_json,
            out_json,
            conway_json,
            alonzo_json,
            fee_buffer,
            overrides: vec![RedeemerOverrideSpec {
                tag: RedeemerTag::Mint,
                index: None,
                new_units: ExUnits {
                    mem: mint_mem,
                    steps: mint_steps,
                },
            }],
            collateral_txid,
            collateral_index,
        });
    }

    let fee_buffer = parse_u64_arg(raw_args[4].clone(), "fee-buffer")?;
    let mut overrides = Vec::new();
    let mut collateral_txid = None;
    let mut collateral_index = None;

    let mut cursor = 5;
    while cursor < raw_args.len() {
        match raw_args[cursor].as_str() {
            "--redeemer" => {
                let value = raw_args.get(cursor + 1).ok_or_else(usage)?;
                overrides.push(parse_redeemer_override(value)?);
                cursor += 2;
            }
            "--collateral-txid" => {
                collateral_txid = Some(raw_args.get(cursor + 1).cloned().ok_or_else(usage)?);
                cursor += 2;
            }
            "--collateral-index" => {
                collateral_index = Some(parse_u64_arg(
                    raw_args.get(cursor + 1).cloned().ok_or_else(usage)?,
                    "collateral-index",
                )?);
                cursor += 2;
            }
            other => return Err(format!("unknown argument `{other}`\n{}", usage())),
        }
    }

    if overrides.is_empty() {
        return Err("at least one --redeemer override is required".to_string());
    }
    if collateral_txid.is_some() ^ collateral_index.is_some() {
        return Err(
            "collateral override requires both --collateral-txid and --collateral-index"
                .to_string(),
        );
    }

    Ok(CliSpec {
        in_json,
        out_json,
        conway_json,
        alonzo_json,
        fee_buffer,
        overrides,
        collateral_txid,
        collateral_index,
    })
}

fn replace_exunits_in_redeemers(
    redeemers: &mut Redeemers,
    overrides: &[RedeemerOverrideSpec],
) -> Result<Vec<(RedeemerOverrideSpec, ExUnits)>, String> {
    let mut applied = Vec::new();

    for override_spec in overrides {
        let mut matched = false;
        match redeemers {
            Redeemers::List(items) => {
                for redeemer in items.iter_mut() {
                    if redeemer.tag != override_spec.tag {
                        continue;
                    }
                    if let Some(index) = override_spec.index {
                        if redeemer.index != index {
                            continue;
                        }
                    }
                    applied.push((*override_spec, redeemer.ex_units));
                    redeemer.ex_units = override_spec.new_units;
                    matched = true;
                }
            }
            Redeemers::Map(items) => {
                for (key, value) in items.iter_mut() {
                    if key.tag != override_spec.tag {
                        continue;
                    }
                    if let Some(index) = override_spec.index {
                        if key.index != index {
                            continue;
                        }
                    }
                    applied.push((*override_spec, value.ex_units));
                    value.ex_units = override_spec.new_units;
                    matched = true;
                }
            }
        }
        if !matched {
            let label = match override_spec.index {
                Some(index) => format!("{:?}[{}]", override_spec.tag, index),
                None => format!("{:?}[*]", override_spec.tag),
            };
            return Err(format!("redeemer override target not found: {label}"));
        }
    }

    Ok(applied)
}

fn override_collateral_input(
    body: &mut TransactionBody,
    txid_hex: Option<String>,
    index: Option<u64>,
) -> Result<(), String> {
    let (Some(txid_hex), Some(index)) = (txid_hex, index) else {
        return Ok(());
    };

    let txid = hex::decode(&txid_hex).map_err(|e| format!("decode collateral-txid: {e}"))?;
    let txid: [u8; 32] = txid
        .try_into()
        .map_err(|_| "collateral-txid must be 32 bytes".to_string())?;

    let collateral: NonEmptySet<_> = vec![TransactionInput {
        transaction_id: txid.into(),
        index,
    }]
    .try_into()
    .map_err(|_| "collateral set cannot be empty".to_string())?;
    body.collateral = Some(collateral);

    Ok(())
}

fn main() -> Result<(), String> {
    let cli = parse_cli_spec()?;

    let tx_json: TxJson = serde_json::from_str(
        &fs::read_to_string(&cli.in_json)
            .map_err(|e| format!("read {}: {e}", cli.in_json.display()))?,
    )
    .map_err(|e| format!("parse {}: {e}", cli.in_json.display()))?;
    let conway: ConwayGenesis = serde_json::from_str(
        &fs::read_to_string(&cli.conway_json)
            .map_err(|e| format!("read {}: {e}", cli.conway_json.display()))?,
    )
    .map_err(|e| format!("parse {}: {e}", cli.conway_json.display()))?;
    let alonzo: AlonzoGenesis = serde_json::from_str(
        &fs::read_to_string(&cli.alonzo_json)
            .map_err(|e| format!("read {}: {e}", cli.alonzo_json.display()))?,
    )
    .map_err(|e| format!("parse {}: {e}", cli.alonzo_json.display()))?;

    let tx_bytes = hex::decode(&tx_json.cbor).map_err(|e| format!("decode tx cbor: {e}"))?;
    let tx: Tx = minicbor::decode(&tx_bytes).map_err(|e| format!("decode tx: {e}"))?;
    let mut body = tx.transaction_body.unwrap();
    let mut witness = tx.transaction_witness_set.unwrap();

    witness.vkeywitness = None;

    let redeemers_raw = witness
        .redeemer
        .take()
        .ok_or_else(|| "transaction has no redeemers".to_string())?;
    let mut redeemers = redeemers_raw.unwrap();
    let applied = replace_exunits_in_redeemers(&mut redeemers, &cli.overrides)?;

    let delta_fee = applied
        .into_iter()
        .map(|(override_spec, old_units)| {
            fee_delta(old_units, override_spec.new_units, &alonzo.execution_prices)
        })
        .fold(cli.fee_buffer, |acc, value| acc.saturating_add(value));

    body.fee = body
        .fee
        .checked_add(delta_fee)
        .ok_or_else(|| "fee overflow".to_string())?;

    let change_output = body
        .outputs
        .last_mut()
        .ok_or_else(|| "transaction has no outputs".to_string())?;
    adjust_output_coin(change_output, delta_fee)?;

    override_collateral_input(&mut body, cli.collateral_txid, cli.collateral_index)?;

    witness.redeemer = Some(KeepRaw::from(redeemers));

    let language_views = LanguageViews::from_iter([(2, conway.plutus_v3_cost_model)]);
    let script_data_hash = ScriptData::build_for(&witness, &Some(language_views))
        .ok_or_else(|| "failed to build script data for witness set".to_string())?
        .hash();
    body.script_data_hash = Some(script_data_hash);

    let tx_hash = body.compute_hash();
    let final_tx = Tx {
        transaction_body: KeepRaw::from(body),
        transaction_witness_set: KeepRaw::from(witness),
        success: tx.success,
        auxiliary_data: tx.auxiliary_data,
    };

    let final_cbor = minicbor::to_vec(&final_tx).map_err(|e| format!("encode tx: {e}"))?;

    let out = TxJsonOut {
        cbor: hex::encode(final_cbor),
        hash: hex::encode(tx_hash),
    };

    fs::write(
        &cli.out_json,
        serde_json::to_string_pretty(&out).map_err(|e| format!("encode out json: {e}"))?,
    )
    .map_err(|e| format!("write {}: {e}", cli.out_json.display()))?;

    Ok(())
}
