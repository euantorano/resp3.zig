const std = @import("std");
const math = std.math;
const fmt = std.fmt;

const assertOrPanic = std.debug.assertOrPanic;

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
//    pub Map = '%',
    pub Set = '~',
//    pub Attribute = '|',
//    pub Push = '>',
//    pub Hello = 'H',
//   pub BigNumber = '('
};

pub const Error = struct {
    pub Code: []const u8,
    pub Message: []const u8,
};

pub const VerbatimStringType = enum {
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
    pub Value: []const u8,
};

pub const Resp3Value = union(Resp3Type) {
    pub Array: []const Resp3Value,
    pub BlobString: []const u8,
    pub SimpleString: []const u8,
    pub SimpleError: Error,
    pub Number: i64,
    pub Null: void,
    // TODO: Double
    pub Boolean: bool,
    pub BlobError: Error,
    pub VerbatimString: VerbatimString,
    // TODO: Map
    pub Set: []const Resp3Value, // TODO: proper set type

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
            Resp3Value.Set => |set| blk: {
                // * (1) + array_len_len + \r (1) + \n (1) + elements_len
                break :blk lenOfSliceOfValues(set);
            }
        };
    }

    fn get_string_length_for_int(val: var) usize {
        return if (val == 0) 1 else (@intCast(usize, math.log10(val) + 1));
    }

    fn lenOfSliceOfValues(values: []const Resp3Value) usize {
        const array_len_len = get_string_length_for_int(values.len);

        var elements_len: usize = 0;

        for (values) |entry| {
            elements_len += entry.encodedLength();
        }

        // start_char (1) + array_len_len + \r (1) + \n (1) + elements_len
        return 3 + array_len_len + elements_len;
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
    const str = "Some string";
    const verbatim_string = VerbatimString {
        .Type = VerbatimStringType.Text,
        .Value = str[0..],
    };
    const val = Resp3Value { .VerbatimString = verbatim_string };
    const expected = "=15\r\ntxt:Some string\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Array of Number" {
    const num_1 = Resp3Value { .Number = 1 };
    const num_2 = Resp3Value { .Number = 2 };
    const num_3 = Resp3Value { .Number = 3 };
    const arr = []Resp3Value{ 
        num_1, 
        num_2, 
        num_3,
    };
    const val = Resp3Value { .Array = &arr };
    const expected = "*3\r\n:1\r\n:2\r\n:3\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for Set of mixed types" {
    const orange = Resp3Value { .SimpleString = &"orange" };
    const apple = Resp3Value { .SimpleString = &"apple" };
    const true_val = Resp3Value { .Boolean = true };
    const number_100 = Resp3Value { .Number = 100 };
    const number_999 = Resp3Value { .Number = 999 };
    const set = []Resp3Value{ 
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