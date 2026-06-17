use aiken/builtin.{bls12_381_g1_neg}
use aiken/crypto/bitwise.{State}
use aiken/crypto/bls12_381/g1.{decompress, generator}
use aiken/crypto/bls12_381/g2.{decompress as decompress_g2}
use aiken/crypto/bls12_381/scalar.{Scalar, from_int}

pub const p1_commitment: ByteArray =
  #"b92b34a4b9931fe530cae3dd411e7f9a011fdd5d56e223f90a051c68a16eb680794c053d0a68c6193d3b8039fb67ddcc"

pub const p2_commitment: ByteArray =
  #"94ddbd6379d0d99c9ac4ce29013edabbd38d2c1ec86f4ccf79aa2b5d3e6d36d6e3cf1270f934ef75496b03bd947cbcf2"

pub const p3_commitment: ByteArray =
  #"a558ba4663777b00f7d40366541719574bd40d1566308789c5b0cd36835e75e058227c62428051d76af27cd2f8ac5a37"

pub const p4_commitment: ByteArray =
  #"83eb459c7e6aa39147410c36a61b73a8ebc128eda9cbba9268a745d77ddb10431a895a7ff8353769884bb7a7965a903b"

pub const p5_commitment: ByteArray =
  #"8212cf1ba90b6664e0705b2e17e330496d8795b4d7459ef8e758edd829a157bb8bf8293b6ffdc3fd93d44217c3097376"

pub const p6_commitment: ByteArray =
  #"8d18ec9832646af7479cf24b5e8aab20d76b2a500501ea9e2677dc0d54d8c76a19b5d54f4b9244f49b9f6599997fe96d"

pub const p7_commitment: ByteArray =
  #"a16adb03db9cbdc045607d9bddb268ea04268b45402e11e3003eed30df19e4a83c9f3b39328cf03d907067f855e4fba9"

pub const p8_commitment: ByteArray =
  #"930fe699833ca97aeebff2b3abfc539dddfd08a26d41ba9d472e3df29dbd9d4ae8701bbfd0c2a224ede6c0d59a45df57"

pub const p9_commitment: ByteArray =
  #"83779cc7c2593874699cf28b55b84d09d0303f52c6f3410e0e7746c5f27df5c1c5954649450f4a919b273221307e025f"

pub const p10_commitment: ByteArray =
  #"8a4a684b725d2aa3a2deb144f6a0e73a3b3081bcf3255f2e6b8b4e2a1d9445f56b64ef1312ec6710c0d22824dca9620c"

pub const f1_commitment: ByteArray =
  #"b9ae2f53c0d60dd02d03cf7569824c20dd029e7d221913a42b38bf95816721eb8c62511de539e2788fefe586024f15d2"

pub const f2_commitment: ByteArray =
  #"b1d9d99860ae8e9e9c1ff9e7b711ccee2802f1b2625c310d9d125e149e0eabfb8b1cb4c596d56759d75f1a41df96312f"

pub const f3_commitment: ByteArray =
  #"953c403860d47e3463d7be3c4b970278850b4ff6232eb4feabf2258a61fb9cc956ff20f3efc0fab5b1e8d5320f5da5cc"

pub const f4_commitment: ByteArray =
  #"91686b263d891754e781b4230c0b75620f45ef65447a068b029da203b117bd4ff539077a3c080566934cb13d4e353473"

pub const f5_commitment: ByteArray =
  #"92cc87530d7d388f1337b1dd603432279f92b83a071feb19c3618b0573455e8ceefc628020a5f2d6816594501171cece"

pub const f6_commitment: ByteArray =
  #"8aac1fb817904ba16d79606a74ec517ad212006a0394bf12e4dd34abd625c791de4d451ff8024399e5178419ce36063f"

pub const f7_commitment: ByteArray =
  #"a9c277cb4206baa5c596148080da02cf8a1aa124c7afcb4e6f6432461233319529e3fb1a0872bb6eb9f22831ef169729"

pub const f8_commitment: ByteArray =
  #"9399479d9466eb2a5a2e5c3a9d6dd277312b7a092f96417bf6c15025b59ebf2d7692e75d3ed29169f682d4f13577a6f9"

pub const f9_commitment: ByteArray =
  #"b2970063b9797ab0c60862a8b853803601afe89d3ad138b4a26c0937c2752af5072f54530eeba45feb92990afff292fe"

pub const f10_commitment: ByteArray =
  #"b4acb92c32b6669767e8dc73a375866f64adf79acdbe1911d8a4a29c7af7af32cf9c9190cd6ab2125a944082ddc8ed74"

pub const f11_commitment: ByteArray =
  #"ac69e9b29a660bfbf6e97a065092138eccf8da4dba535c569900e688d7109e03ffbdc233ed6a6e4e99be9b3bde546085"

pub const f12_commitment: ByteArray =
  #"8e6d929886e82fd509ccffe4a630b83a793cb0c4e4fc13b0f192342feb864d8ca20270450461de1bc845c9107a0532da"

pub const f13_commitment: ByteArray =
  #"9727a5aaf88e66d58e02bdcb1f21e872cd7fa6a5defa104adb7c0d677dc2a98d7e6f614bada259a32fc1c959d3a0668f"

pub const f14_commitment: ByteArray =
  #"88012e6ab9642d5c691b28bd290f1fb5ddec297d454c5f61cf772145d28a9c933a0fd44b59f5906f6343259408b073de"

pub const f15_commitment: ByteArray =
  #"c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

pub const f16_commitment: ByteArray =
  #"8cca23c25eddf7b0618c414611811d97b97eee617d9a7eb8076de7c3d66b4f768b477d6a2a2425ffd14a6260fdd7dad2"

pub const f17_commitment: ByteArray =
  #"931d75250af0122cd7ccd8504a554f00a909a73cd9ad3d59110132efd78eb25a13ec2b7699e4a598922f14e7b43163a4"

pub const f18_commitment: ByteArray =
  #"87b82501b39a39d915598c22742d5d3d50a4d933650f4cfc3a0a1ab2f95a37670ee4e5a7a24861bdc41aac14af949d7d"

pub const f19_commitment: ByteArray =
  #"a159b436122b44ebcd1ef566e3f9e23ef2190989665924898c070899048f205752cb2d852b86798730e4cfcd9f5471bf"

pub const f20_commitment: ByteArray =
  #"b3fe2a8f2ff6ed3899dc6465dae765837d6b3aaef987a95260e6ea68fe1ba7f28e29f1b0578f13828d618bfd9366b2a5"

pub const f21_commitment: ByteArray =
  #"8c9a7cc542f5f01e1c226a73f143947a0ddd66f3e81665dd65f23c432aa0dfe23203b64ff3853e55407ff7e305b1b678"

pub const f22_commitment: ByteArray =
  #"a4f2f86ac75d12e4f86bb4fb6cd3f5e21d70d4c253376b4395c5c7e0aa86a703df915bd292398895aca622ed5591564b"

pub const g2_const: G2Element =
  decompress_g2(
    #"8985344664badd2aa2d24167fa478ec03a6fc76eb05ba1c3fac9dd88b74a44ccdd5d088bb6975c06a8df4b1006f8e5350adbf82b3a758613f56d4519da62f9075adfdd882b35f35a55f532471191348924a5c3858529f83cfb032cc8962f7922",
  )

pub const neg_g1_generator: ByteArray =
  #"b7f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"

pub const omega: State<Scalar> =
  from_int(0x56624634b500a166dc86b01c0d477fa6ae4622f6a9152435034d2ff22a5ad9e1)

pub const omega_inv: State<Scalar> =
  from_int(0x281f74790b85a216fd013df1f683bf99a14c38253fdb838cd7a1f5bc8f529599)

pub const barycentric_weight: State<Scalar> =
  from_int(0x73ebd79c8c50d6d23e190b20a981b17df3a8550c6ff25c059003ffff00040001)

pub const transcript_rep: State<Scalar> =
  from_int(0x53f66e0660806a16acb5039ebf52758c0bdb4e36661de676db9fe94d1356bc71)

pub const blinding_factors: Int = 6

// this test is for checking how much budget is used when G1 constants are used in script, assertions are only to force use of the constant
test cpu_mem_budget_check() {
  let f1_commitment = decompress(f1_commitment)
  expect f1_commitment == f1_commitment
  let f2_commitment = decompress(f2_commitment)
  expect f2_commitment == f2_commitment
  let f3_commitment = decompress(f3_commitment)
  expect f3_commitment == f3_commitment
  let f4_commitment = decompress(f4_commitment)
  expect f4_commitment == f4_commitment
  let f5_commitment = decompress(f5_commitment)
  expect f5_commitment == f5_commitment
  let f6_commitment = decompress(f6_commitment)
  expect f6_commitment == f6_commitment
  let f7_commitment = decompress(f7_commitment)
  expect f7_commitment == f7_commitment
  let f8_commitment = decompress(f8_commitment)
  expect f8_commitment == f8_commitment
  let f9_commitment = decompress(f9_commitment)
  expect f9_commitment == f9_commitment
  let f10_commitment = decompress(f10_commitment)
  expect f10_commitment == f10_commitment
  let f11_commitment = decompress(f11_commitment)
  expect f11_commitment == f11_commitment
  let f12_commitment = decompress(f12_commitment)
  expect f12_commitment == f12_commitment
  let f13_commitment = decompress(f13_commitment)
  expect f13_commitment == f13_commitment
  let f14_commitment = decompress(f14_commitment)
  expect f14_commitment == f14_commitment
  let f15_commitment = decompress(f15_commitment)
  expect f15_commitment == f15_commitment
  let f16_commitment = decompress(f16_commitment)
  expect f16_commitment == f16_commitment
  let f17_commitment = decompress(f17_commitment)
  expect f17_commitment == f17_commitment
  let f18_commitment = decompress(f18_commitment)
  expect f18_commitment == f18_commitment
  let f19_commitment = decompress(f19_commitment)
  expect f19_commitment == f19_commitment
  let f20_commitment = decompress(f20_commitment)
  expect f20_commitment == f20_commitment
  let f21_commitment = decompress(f21_commitment)
  expect f21_commitment == f21_commitment
  let f22_commitment = decompress(f22_commitment)
  expect f22_commitment == f22_commitment
  let p1_commitment = decompress(p1_commitment)
  expect p1_commitment == p1_commitment
  let p2_commitment = decompress(p2_commitment)
  expect p2_commitment == p2_commitment
  let p3_commitment = decompress(p3_commitment)
  expect p3_commitment == p3_commitment
  let p4_commitment = decompress(p4_commitment)
  expect p4_commitment == p4_commitment
  let p5_commitment = decompress(p5_commitment)
  expect p5_commitment == p5_commitment
  let p6_commitment = decompress(p6_commitment)
  expect p6_commitment == p6_commitment
  let p7_commitment = decompress(p7_commitment)
  expect p7_commitment == p7_commitment
  let p8_commitment = decompress(p8_commitment)
  expect p8_commitment == p8_commitment
  let p9_commitment = decompress(p9_commitment)
  expect p9_commitment == p9_commitment
  let p10_commitment = decompress(p10_commitment)
  expect p10_commitment == p10_commitment
  expect g2_const == g2_const
}

test neg_g2_generator() {
  let neg_g1 = bls12_381_g1_neg(generator)
  expect decompress(neg_g1_generator) == neg_g1
}
