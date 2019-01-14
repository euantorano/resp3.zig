const std = @import("std");
const math = std.math;
const fmt = std.fmt;
const HashMap = std.hash_map.HashMap;
const mem = std.mem;

const hashes = @import("./hashes.zig");

const assertOrPanic = std.debug.assertOrPanic;
const debugAllocator = std.debug.global_allocator;

pub const Resp3Type = packed enum(u8) {
    pub Array = '*',
    pub BlobString = '$',
    pub SimpleString = '+',
    pub SimpleError = '-',
    pub Number = ':',
    pub Null = '_',
//    pub Double = ',',
    pub Boolean = '#',
    pub BlobError = '!',
    pub VerbatimString = '=',
    pub Map = '%',
    pub Set = '~',
//    pub Attribute = '|',
//    pub Push = '>',
//    pub Hello = 'H',
//   pub BigNumber = '('
};

pub const Error = struct {
    pub Code: []u8,
    pub Message: []u8,

    pub fn equals(a: Error, b: Error) bool {
        return mem.eql(u8, a.Code, b.Code) and mem.eql(u8, a.Message, b.Message);
    }

    pub fn hash(self: Error) u32 {
        const mixed = hashes.mix(hashes.hashString(self.Code), hashes.hashString(self.Message));

        return hashes.finalize(mixed);
    }
};

test "Error::equals for two of the same errors" {
    const err_1 = Error {
        .Code = &"ERR",
        .Message = &"this is the error description",
    };
    const err_2 = Error {
        .Code = &"ERR",
        .Message = &"this is the error description",
    };

    assertOrPanic(err_1.equals(err_2));
}

test "Error::equals for two different errors" {
    const err_1 = Error {
        .Code = &"ERR",
        .Message = &"this is the error description",
    };
    const err_2 = Error {
        .Code = &"ERR",
        .Message = &"this is not the error description",
    };

    assertOrPanic(!err_1.equals(err_2));
}

pub const VerbatimStringType = packed enum(u1) {
    pub Text,
    pub Markdown,

    pub fn to_string(self: VerbatimStringType) [3]u8 {
        return switch (self) {
            VerbatimStringType.Text => "txt",
            VerbatimStringType.Markdown => "mkd",
        };
    }
};

pub const VerbatimString = struct {
    pub Type: VerbatimStringType,
    pub Value: []u8,

    pub fn equals(a: VerbatimString, b: VerbatimString) bool {
        return (a.Type == b.Type) and mem.eql(u8, a.Value, b.Value);
    }

    pub fn hash(self: VerbatimString) u32 {
        const mixed = hashes.mix(@enumToInt(self.Type), hashes.hashString(self.Value));

        return hashes.finalize(mixed);
    }
};

test "VerbatimString::equals for two of the same verbatim strings" {
    const verbatim_string_1 = VerbatimString {
        .Type = VerbatimStringType.Text,
        .Value = &"Some string",
    };
    const verbatim_string_2 = VerbatimString {
        .Type = VerbatimStringType.Text,
        .Value = &"Some string",
    };

    assertOrPanic(verbatim_string_1.equals(verbatim_string_2));
}

test "VerbatimString::equals for two different verbatim strings" {
    const verbatim_string_1 = VerbatimString {
        .Type = VerbatimStringType.Text,
        .Value = &"Some string",
    };
    const verbatim_string_2 = VerbatimString {
        .Type = VerbatimStringType.Text,
        .Value = &"Some string 2",
    };

    assertOrPanic(!verbatim_string_1.equals(verbatim_string_2));
}

const Resp3ValueHashMap = HashMap(Resp3Value, Resp3Value, Resp3Value.hash, Resp3Value.equals);

pub const Resp3Value = union(Resp3Type) {
    pub Array: []Resp3Value,
    pub BlobString: []u8,
    pub SimpleString: []u8,
    pub SimpleError: Error,
    pub Number: i64,
    pub Null: void,
    // TODO: Double
    pub Boolean: bool,
    pub BlobError: Error,
    pub VerbatimString: VerbatimString,
    pub Map: Resp3ValueHashMap,
    pub Set: []Resp3Value, // TODO: proper set type

    // TODO: init/deinit to deinit Resp3ValueHashMap?

    pub fn encodedLength(self: Resp3Value) usize {
        return switch (self) {
            Resp3Value.Array => |arr| blk: {
                // * (1) + array_len_len + \r (1) + \n (1) + elements_len
                break :blk lenOfSliceOfValues(arr);
            },
            Resp3Value.BlobString => |str| blk: {
                const str_len = str.len;
                const length_len = get_string_length_for_int(str_len);

                // $ (1) + \r (1) + \n (1) + str_len + \r (1) + \n (1)
                break :blk @intCast(usize, 5 + str_len + length_len);
            },
            Resp3Value.SimpleString => |str| blk: {
                const str_len = str.len;

                // + (1) + str_len + \r (1) + \n (1)
                break :blk @intCast(usize, 3 + str.len);
            },
            Resp3Value.SimpleError => |err| blk: {
                const err_code_len = err.Code.len;
                const err_msg_len = err.Message.len;

                // - (1) + err_code_len + ' ' (1) + \r (1) + \n (1)
                break :blk @intCast(usize, 4 + err_code_len + err_msg_len);
            },
            Resp3Value.Number => |num| blk: {
                const num_len = get_string_length_for_int(num);

                // : (1) + num_len + \r (1) + \n (1)
                break :blk @intCast(usize, 3 + num_len);
            },
            Resp3Value.Null => @intCast(usize, 3),
            Resp3Value.Boolean => @intCast(usize, 4),
            Resp3Value.BlobError => |err| blk: {
                const err_code_len = err.Code.len;
                const err_msg_len = err.Message.len;
                const length_len = get_string_length_for_int(err_code_len + err_msg_len);

                // ! (1) + length_len + \r (1) + \n (1) + err_code_len + ' ' (1) + err_msg_len + \r (1) + \n (1)
                break :blk @intCast(usize, 6 + length_len + err_code_len + err_msg_len);
            },
            Resp3Value.VerbatimString => |str| blk: {
                const str_len = str.Value.len;
                // type (3) + : (1) + str_len
                const total_str_len = str_len + 4;
                const length_len = get_string_length_for_int(total_str_len);

                // = (1) + length_len + \r (1) + \n (1) + total_str_len + \r (1) + \n (1)
                break :blk @intCast(usize, 5 + length_len + total_str_len);
            },
            Resp3Value.Map => |map| blk: {
                break :blk lenOfMapOfValues(map);
            },
            Resp3Value.Set => |set| blk: {
                // * (1) + array_len_len + \r (1) + \n (1) + elements_len
                break :blk lenOfSliceOfValues(set);
            },
        };
    }

    fn get_string_length_for_int(val: var) usize {
        return if (val == 0) 1 else (@intCast(usize, math.log10(val) + 1));
    }

    fn lenOfSliceOfValues(values: []Resp3Value) usize {
        const array_len_len = get_string_length_for_int(values.len);

        var elements_len: usize = 0;

        for (values) |entry| {
            elements_len += entry.encodedLength();
        }

        // start_char (1) + array_len_len + \r (1) + \n (1) + elements_len
        return 3 + array_len_len + elements_len;
    }

    fn lenOfMapOfValues(values: Resp3ValueHashMap) usize {
       const map_len_len = get_string_length_for_int(values.count());
    
        var elements_len: usize = 0;
    
        var it = values.iterator();
        while (it.next()) |entry| {
            elements_len += entry.key.encodedLength();
            elements_len += entry.value.encodedLength();
        }
    
        // start_char(1) + map_len_len + \r (1) + \n (1) + elements_len
        return 3 + map_len_len + elements_len;
    }

    pub fn equals(a: Resp3Value, b: Resp3Value) bool {
        if (Resp3Type(a) != Resp3Type(b)) {
            return false;
        }

        return switch (a) {
            Resp3Value.Array => |a_arr| blk: {
                const b_arr = b.Array;

                if (a_arr.len != b_arr.len) {
                    break :blk false;
                }

                var i: usize = 0;
                while (i < a_arr.len) {
                    const a_entry = a_arr[i];
                    const b_entry = b_arr[i];

                    if (!(a_entry.equals(b_entry))) {
                        break :blk false;
                    }

                    i += 1;
                }

                break :blk true;
            },
            Resp3Value.BlobString => |a_str| blk: {
                const b_str = b.BlobString;

                break :blk mem.eql(u8, a_str, b_str);
            },
            Resp3Value.SimpleString => |a_str| blk: {
                const b_str = b.SimpleString;

                break :blk mem.eql(u8, a_str, b_str);
            },
            Resp3Type.SimpleError => |a_err| blk: {
                const b_err = b.SimpleError;

                break :blk a_err.equals(b_err);
            },
            Resp3Value.Number => |a_num| blk: {
                const b_num = b.Number;

                break :blk (a_num == b_num);
            },
            Resp3Value.Null => true,
            Resp3Value.Boolean => |a_bool| blk: {
                const b_bool = b.Boolean;

                break :blk (a_bool == b_bool);
            },
            Resp3Value.BlobError => |a_err| blk: {
                const b_err = b.BlobError;

                break :blk a_err.equals(b_err);
            },
            Resp3Value.VerbatimString => |a_str| blk: {
                const b_str = b.VerbatimString;

                break :blk a_str.equals(b_str);
            },
            Resp3Value.Map => |a_map| blk: {
                const b_map = b.Map;

                if (a_map.count() != b_map.count()) {
                    break :blk false;
                }

                var it = a_map.iterator();
                while (it.next()) |entry| {
                    if (b_map.get(entry.key)) |b_entry| {
                        if (!entry.value.equals(b_entry.value)) {
                            break :blk false;
                        }
                    } else {
                        break :blk false;
                    }
                }

                break :blk true;
            },
            Resp3Value.Set => |a_set| blk: {
                const b_set = b.Set;

                if (a_set.len != b_set.len) {
                    break :blk false;
                }

                var i: usize = 0;
                while (i < a_set.len) {
                    const a_entry = a_set[i];
                    const b_entry = b_set[i];

                    if (!(a_entry.equals(b_entry))) {
                        break :blk false;
                    }

                    i += 1;
                }

                break :blk true;
            },
        };
    }

    pub fn hash(self: Resp3Value) u32 {
        var result: u32 = 0;

        const typeOfValue = Resp3Type(self);
        const typeOfValueInt = @enumToInt(typeOfValue);

        result = hashes.mix(result, typeOfValueInt);

        const child = switch (self) {
            Resp3Value.Array => |arr| blk: {
                var sum: u32 = 0;

                for (arr) |item| {
                    sum = hashes.mix(sum, item.hash());
                }

                break :blk hashes.finalize(sum);
            },
            Resp3Value.BlobString => |str| blk: {
                break :blk hashes.hashString(str);
            },
            Resp3Value.SimpleString => |str| blk: {
                break :blk hashes.hashString(str);
            },
            Resp3Type.SimpleError => |err| blk: {
                break :blk err.hash();
            },
            Resp3Value.Number => |num| blk: {
                break :blk hashes.hashInteger64(num);
            },
            Resp3Value.Null => 0,
            Resp3Value.Boolean => |bool_val| blk: {
                break :blk @boolToInt(bool_val);
            },
            Resp3Value.BlobError => |err| blk: {
                break :blk err.hash();
            },
            Resp3Value.VerbatimString => |str| blk: {
                break :blk str.hash();
            },
            Resp3Value.Map => |values| blk: {
                var sum: u32 = 0;

                var it = values.iterator();
                while (it.next()) |entry| {
                    sum = hashes.mix(sum, entry.key.hash());
                    sum = hashes.mix(sum, entry.value.hash());
                }

                break :blk hashes.finalize(sum);
            },
            Resp3Value.Set => |set| blk: {
                var sum: u32 = 0;

                for (set) |item| {
                    sum = hashes.mix(sum, item.hash());
                }

                break :blk hashes.finalize(sum);
            },
        };

        result = hashes.mix(result, child);

        return hashes.finalize(result);
    }
};

test "Resp3Value::encodedLength for BlobString" {
    const val = Resp3Value { .BlobString = &"helloworld" };
    const expected = "$11\r\nhelloworld\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for SimpleString" {
    const val = Resp3Value { .SimpleString = &"hello world" };
    const expected = "+hello world\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for SimpleError" {
    const err = Error {
        .Code = &"ERR",
        .Message = &"this is the error description",
    };
    const val = Resp3Value { .SimpleError = err };
    const expected = "-ERR this is the error description\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Number" {
    const val = Resp3Value { .Number = 1234 };
    const expected = ":1234\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Null" {
    const val = Resp3Value { .Null = undefined };
    const expected = "_\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Boolean" {
    const val = Resp3Value { .Boolean = true };
    const expected = "#t\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for BlobError" {
    const err = Error {
        .Code = &"SYNTAX",
        .Message = &"invalid syntax",
    };
    const val = Resp3Value { .BlobError = err };
    const expected = "!21\r\nSYNTAX invalid syntax\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for VerbatimString" {
    const verbatim_string = VerbatimString {
        .Type = VerbatimStringType.Text,
        .Value = &"Some string",
    };
    const val = Resp3Value { .VerbatimString = verbatim_string };
    const expected = "=15\r\ntxt:Some string\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Array of Number" {
    const num_1 = Resp3Value { .Number = 1 };
    const num_2 = Resp3Value { .Number = 2 };
    const num_3 = Resp3Value { .Number = 3 };
    var arr = []Resp3Value{ 
        num_1, 
        num_2, 
        num_3,
    };
    const val = Resp3Value { .Array = &arr };
    const expected = "*3\r\n:1\r\n:2\r\n:3\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Map of [sring, num]" {
    var map = Resp3ValueHashMap.init(debugAllocator);
    defer map.deinit();

    const key1 = Resp3Value { .SimpleString = &"first" };
    const value1 = Resp3Value { .Number = 1 };
    assertOrPanic((try map.put(key1, value1)) == null);

    const key2 = Resp3Value { .SimpleString = &"second" };
    const value2 = Resp3Value { .Number = 2 };
    assertOrPanic((try map.put(key2, value2)) == null);

    const val = Resp3Value { .Map = map };
    const expected = "%2\r\n+first\r\n:1\r\n+second\r\n:2\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Set of mixed types" {
    const orange = Resp3Value { .SimpleString = &"orange" };
    const apple = Resp3Value { .SimpleString = &"apple" };
    const true_val = Resp3Value { .Boolean = true };
    const number_100 = Resp3Value { .Number = 100 };
    const number_999 = Resp3Value { .Number = 999 };
    var set = []Resp3Value{ 
        orange, 
        apple, 
        true_val,
        number_100,
        number_999,
    };
    const val = Resp3Value { .Set = &set };
    const expected = "~5\r\n+orange\r\n+apple\r\n#t\r\n:100\r\n:999\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::equals for two different types" {
    const val_1 = Resp3Value { .Boolean = true };
    const val_2 = Resp3Value { .Number = 1 };

    assertOrPanic(val_1.equals(val_2) == false);
}

test "Resp3Value::equals for two of the same types and values" {
    const val_1 = Resp3Value { .Boolean = true };
    const val_2 = Resp3Value { .Boolean = true };

    assertOrPanic(val_1.equals(val_2) == true);
}

test "Resp3Value::equals for two of the same types but different values" {
    const val_1 = Resp3Value { .Boolean = true };
    const val_2 = Resp3Value { .Boolean = false };

    assertOrPanic(val_1.equals(val_2) == false);
}

test "Resp3Value::equals for two maps that are equal" {
    var map = Resp3ValueHashMap.init(debugAllocator);
    defer map.deinit();


    const key1 = Resp3Value { .SimpleString = &"first" };
    const value1 = Resp3Value { .Number = 1 };
    assertOrPanic((try map.put(key1, value1)) == null);

    const key2 = Resp3Value { .SimpleString = &"second" };
    const value2 = Resp3Value { .Number = 2 };
    assertOrPanic((try map.put(key2, value2)) == null);

    const val = Resp3Value { .Map = map };
    const val2 = Resp3Value { .Map = map };

    assertOrPanic(val.equals(val2));
}