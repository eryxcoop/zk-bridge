use aiken/builtin.{integer_to_bytearray}
use aiken/primitive/bytearray
use aiken/primitive/string

/// This function converts an integer of eight bytes into a `ByteArray` in big endian.
/// It exists because Mithril usually converts them in this way to append them to an input string.
/// `integer_to_bytearray(endianness: Bool, size: Int, value: Int) -> ByteArray`
/// to_be_bytes for `u64` is: `integer_to_bytearray(True, 8, value)`
pub fn to_be_bytes(value: Int) -> ByteArray {
  integer_to_bytearray(True, 8, value)
}

/// In the Mithril implementation in Rust, they sometimes hash some part of a certificate
/// (e.g., its `CertificateMetadata`) and then append the digest to construct the next input
/// for the hash function. However, each struct's `compute_hash()` function ends with the line
/// `hex::encode(hasher.finalize())`, which means that they are not appending the digest but a hex
/// string representation of the digest. Specifically, this implies appending twice the number of bytes
/// (e.g., an `a` is interpreted like the byte `61` since `'a' == 97 == 0x61`), and it adds overhead to
/// the computation of certificate hashes. If the Mithril implementation addresses this issue, it
/// the performance of the verification of a `MithrilCertificate` would be improved.
///
/// This behaviour could be represented in Aiken by composing the functions `bytearray.to_hex` and
/// `string.to_bytearray`, but the issue is that the `hex` crate in Rust returns a lowercase string,
/// while Aiken's `bytearray.to_hex` returns an uppercase string. This is why this function exists.
/// It lowercases the uppercase hex string obtained from doing the transformation to `digest`.
pub fn digest_to_bytes_of_string(digest: ByteArray) -> ByteArray {
  let hex = bytearray.to_hex(digest)
  let upper_bytes = string.to_bytearray(hex)

  // Lowercase the bytes
  bytearray.foldr(
    upper_bytes,
    #"",
    fn(b, acc) {
      // 'A' = 65, 'F' = 70, 'a' = 97
      let mapped =
        if b >= 65 && b <= 70 {
          b + 32
        } else {
          // A–F -> a–f
          b
        }

      bytearray.push(acc, mapped)
    },
  )
}

test digest_to_bytes_of_string_test() {
  let bytes =
    #"ace019657cd995b0dfbb1ce8721a1092715972c4ae0171cc636ab4a44e6e4279"
  digest_to_bytes_of_string(bytes) == #"61636530313936353763643939356230646662623163653837323161313039323731353937326334616530313731636336333661623461343465366534323739"
}
