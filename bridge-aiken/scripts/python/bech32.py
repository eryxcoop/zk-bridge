BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
BECH32_CHARSET_REV = {char: index for index, char in enumerate(BECH32_CHARSET)}
BECH32_GEN = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]


def bech32_polymod(values: list[int]) -> int:
    checksum = 1
    for value in values:
        top = checksum >> 25
        checksum = ((checksum & 0x1FFFFFF) << 5) ^ value
        for bit, generator in enumerate(BECH32_GEN):
            if (top >> bit) & 1:
                checksum ^= generator
    return checksum


def bech32_hrp_expand(hrp: str) -> list[int]:
    return [ord(char) >> 5 for char in hrp] + [0] + [ord(char) & 31 for char in hrp]


def bech32_verify_checksum(hrp: str, data: list[int]) -> bool:
    return bech32_polymod(bech32_hrp_expand(hrp) + data) == 1


def convertbits(data: list[int], frombits: int, tobits: int, pad: bool) -> list[int]:
    acc = 0
    bits = 0
    result: list[int] = []
    max_value = (1 << tobits) - 1

    for value in data:
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            result.append((acc >> bits) & max_value)

    if pad:
        if bits:
            result.append((acc << (tobits - bits)) & max_value)
    elif bits >= frombits or ((acc << (tobits - bits)) & max_value):
        raise ValueError("invalid bech32 data conversion")

    return result


def payment_key_hash_from_address(address: str) -> str:
    separator_index = address.rfind("1")
    if separator_index <= 0:
        raise ValueError(f"invalid bech32 address: {address}")

    hrp = address[:separator_index]
    data = [BECH32_CHARSET_REV[char] for char in address[separator_index + 1 :]]
    if not bech32_verify_checksum(hrp, data):
        raise ValueError(f"invalid bech32 checksum for address: {address}")

    raw = bytes(convertbits(data[:-6], 5, 8, False))
    if len(raw) < 29:
        raise ValueError(f"address payload too short: {address}")

    return raw[1:29].hex()
