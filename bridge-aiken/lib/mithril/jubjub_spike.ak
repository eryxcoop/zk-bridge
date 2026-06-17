/// Minimal Jubjub arithmetic spike for feasibility testing in Aiken.
///
/// This module is intentionally isolated from production validators. Its goal
/// is to answer a narrow question: does plain Aiken arithmetic for Jubjub point
/// operations already look too expensive before we even attempt Poseidon or the
/// full Mithril genesis Schnorr verifier?
///
/// The measured answer from this spike is categorically **no** for the current
/// bridge architecture:
///
/// - cheap curve-membership checks are fine
/// - but scalar multiplication already explodes to prohibitive execution units
///   in plain Aiken
/// - this happens before adding Poseidon, subgroup validation semantics, or the
///   full Mithril genesis Schnorr transcript
pub type JubjubPoint {
  JubjubPoint { u: Int, v: Int }
}

const jubjub_q =
  0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001

const jubjub_r =
  0xe7db4ea6533afa906673b0101343b00a6682093ccc81082d0970e5ed6f72cb7

const edwards_d =
  0x2a9318e74bfa2b48f5fd9207e6bd7fd4292d7f6d37579d2601065fd6d6343eb1

const identity = JubjubPoint { u: 0, v: 1 }

// `full_generator()` from blstrs' Jubjub implementation.
const generator =
  JubjubPoint {
    u: 0x62edcbb8bf3787c88b0f03ddd60a8187caf55d1b29bf81afe4b3d35df1a7adfe,
    v: 0xb,
  }

// `SchnorrVerificationKey::golden_value()` bytes from mithril-stm.
const golden_vk =
  JubjubPoint {
    u: 0x3e3e3789272ff96f086c740bb2bf9babc4ba22c86d69c568a07d4301a24516ba,
    v: 0x2bda20c8fdbb42c2884609655f2ff161c4f4ee20cfe7d98c2031fd7fa15f3490,
  }

// `StandardSchnorrSignature::golden_value()` response half from mithril-stm.
const golden_response =
  0xd40c25b801ce234919a5eb2fb9edf1a0eab4c9d6510c1f57b558fbd20881f59

fn norm_q(x: Int) -> Int {
  let reduced = x % jubjub_q

  if reduced < 0 {
    reduced + jubjub_q
  } else {
    reduced
  }
}

fn add_q(left: Int, right: Int) -> Int {
  norm_q(left + right)
}

fn sub_q(left: Int, right: Int) -> Int {
  norm_q(left - right)
}

fn mul_q(left: Int, right: Int) -> Int {
  norm_q(left * right)
}

fn inv_q(x: Int) -> Int {
  let reduced = norm_q(x)

  if reduced == 0 {
    fail
  } else {
    norm_q(egcd_go(reduced, jubjub_q, 1, 0))
  }
}

fn egcd_go(u: Int, v: Int, x1: Int, x2: Int) -> Int {
  if u == 1 {
    x1
  } else {
    let q = v / u
    let r = v % u
    let x = x2 - q * x1
    egcd_go(r, u, x, x1)
  }
}

fn point_is_on_curve(point: JubjubPoint) -> Bool {
  let JubjubPoint { u, v } = point
  let uu = mul_q(u, u)
  let vv = mul_q(v, v)
  let lhs = sub_q(vv, uu)
  let rhs = add_q(1, mul_q(edwards_d, mul_q(uu, vv)))

  lhs == rhs
}

fn point_add(left: JubjubPoint, right: JubjubPoint) -> JubjubPoint {
  let JubjubPoint { u: u1, v: v1 } = left
  let JubjubPoint { u: u2, v: v2 } = right
  let uvuv = mul_q(mul_q(u1, u2), mul_q(v1, v2))
  let u_num = add_q(mul_q(u1, v2), mul_q(v1, u2))
  let u_den = add_q(1, mul_q(edwards_d, uvuv))
  let v_num = add_q(mul_q(v1, v2), mul_q(u1, u2))
  let v_den = sub_q(1, mul_q(edwards_d, uvuv))

  JubjubPoint { u: mul_q(u_num, inv_q(u_den)), v: mul_q(v_num, inv_q(v_den)) }
}

fn point_double(point: JubjubPoint) -> JubjubPoint {
  point_add(point, point)
}

fn point_is_identity(point: JubjubPoint) -> Bool {
  point == identity
}

fn scalar_mul(point: JubjubPoint, scalar: Int) -> JubjubPoint {
  if scalar == 0 {
    identity
  } else {
    if scalar % 2 == 0 {
      scalar_mul(point_double(point), scalar / 2)
    } else {
      point_add(point, scalar_mul(point_double(point), scalar / 2))
    }
  }
}

fn repeat_on_curve(point: JubjubPoint, count: Int) -> Bool {
  if count <= 0 {
    True
  } else {
    point_is_on_curve(point) && repeat_on_curve(point, count - 1)
  }
}

test generator_is_on_curve() {
  point_is_on_curve(generator)
}

test golden_vk_is_on_curve() {
  point_is_on_curve(golden_vk)
}

test repeated_vk_curve_checks_benchmark() {
  repeat_on_curve(golden_vk, 20)
}

test scalar_mul_generator_small_benchmark() {
  let result = scalar_mul(generator, 1000)
  point_is_on_curve(result)
}

test scalar_mul_vk_response_benchmark() {
  let result = scalar_mul(golden_vk, golden_response)
  point_is_on_curve(result)
}

test subgroup_order_benchmark() {
  let result = scalar_mul(golden_vk, jubjub_r)
  point_is_on_curve(result)
}
