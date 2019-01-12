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
//    pub Set = '~',
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
    pub Boolean: bool,
    pub BlobError: Error,
    pub VerbatimString: VerbatimString,

    pub fn encodedLength(self: Resp3Value) usize {
        return switch (self) {
            Resp3Value.Array => |arr| blk: {
                const array_len_len = get_string_length_for_int(arr.len);

                var elements_len: usize = 0;

                for (arr) |entry| {
                    elements_len += entry.encodedLength();
                }

                // * (1) + array_len_len + \r (1) + \n (1) + elements_len
                break :blk 3 + array_len_len + elements_len;
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
        };
    }
};

fn get_string_length_for_int(val: var) usize {
    return if (val == 0) 1 else (@intCast(usize, math.log10(val) + 1));
}

test "Resp3Value::encodedLength for BlobString" {
    const str = "helloworld";
    const val = Resp3Value { .BlobString = str[0..] };
    const expected = "$11\r\nhelloworld\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for SimpleString" {
    const str = "hello world";
    const val = Resp3Value { .SimpleString = str[0..] };
    const expected = "+hello world\r\n";

    assertOrPanic(val.encodedLength() == expected.len);
}

test "Resp3Value::encodedLength for SimpleError" {
    const err_code = "ERR";
    const err_message = "this is the error description";
    const err = Error {
        .Code = err_code[0..],
        .Message = err_message[0..],
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
    const err_code = "SYNTAX";
    const err_message = "invalid syntax";
    const err = Error {
        .Code = err_code[0..],
        .Message = err_message[0..],
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