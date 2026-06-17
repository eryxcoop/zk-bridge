use aiken/collection/list
use aiken/primitive/bytearray
use zk/verification.{Single, ZKInputType}

pub fn raw_digest_to_public_inputs(bytes: ByteArray) -> List<Int> {
  bytearray.foldr(bytes, [], fn(b, acc) { [b, ..acc] })
}

fn pack_public_input_chunk(bytes: ByteArray) -> Int {
  list.foldl(
    raw_digest_to_public_inputs(bytes),
    0,
    fn(byte, acc) { acc * 256 + byte },
  )
}

pub fn raw_digest_to_zk_public_inputs(bytes: ByteArray) -> List<ZKInputType> {
  [
    Single(pack_public_input_chunk(bytearray.take(bytes, 16))),
    Single(pack_public_input_chunk(bytearray.drop(bytes, 16))),
  ]
}
