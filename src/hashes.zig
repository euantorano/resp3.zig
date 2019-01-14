/// Hashing functions for various types to be used in a hash map.

const std = @import("std");
const assertOrPanic = std.debug.assertOrPanic;

pub fn mix(a: u32, b: u32) u32 {
    var result: u32 = 0;

    _ = @addWithOverflow(u32, a, b, &result);

    var shifted: u32 = 0;

    _ = @shlWithOverflow(u32, result, 10, &shifted);
    _ = @addWithOverflow(u32, result, shifted, &result);

    shifted = result >> 6;

    result ^= shifted;

    return result;
}

pub fn finalize(hash: u32) u32 {
    var result: u32 = 0;

    var shifted: u32 = 0;

    _ = @shlWithOverflow(u32, hash, 3, &shifted);
    _ = @addWithOverflow(u32, hash, shifted, &result);

    shifted = result >> 11;

    result ^= shifted;

    _ = @shlWithOverflow(u32, result, 15, &shifted);
    _ = @addWithOverflow(u32, result, shifted, &result);

    return result;
}

pub fn hashString(str: []u8) u32 {
    var result: u32 = 0;

    for (str) |entry| {
        result = mix(result, entry);
    }

    return finalize(result);
}

pub fn hashInteger64(int: i64) u32 {
    var arr = []i64{ int };
    const bytes = @sliceToBytes(arr[0..]);

    return hashString(bytes);
}

test "hashString for 2 small simple strings and ensure they are different" {
    const hash1 = hashString(&"test");
    const hash2 = hashString(&"test1");

    assertOrPanic(hash1 != hash2);
}