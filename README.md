# RESP3

This library aims to implement the [RESP3](https://github.com/antirez/RESP3) protocol in [Zig](https://ziglang.org).

It doesn't aim to provide any transport to actually communicate in RESP3, only to be able to parse and encode the protocol itself.

## TODO:

- [ ] Encoding RESP3 commands and responses
	- [X] Define basic types
	- [X] Calculate buffer length for basic types
	- [ ] Define complex types (arrays, maps, sets, etc.)
	- [ ] Calculate buffer length for complex types
	- [ ] Encode basic types to a buffer
	- [ ] Encode complex types to a buffer
- [ ] Decoding RESP3 commands and responses