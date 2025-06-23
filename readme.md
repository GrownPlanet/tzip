# tzip
An extremely simple file compressor written in zig.

## Building
requirements: `zig` (I used 0.14)

To compress a file:
```bash
zig run src/main.zig -- compress [file to compress] [output file]

```

To decompress a file:
```bash
zig run src/main.zig -- decompress [compressed file] [output file]
```

You can also use `zig build-exe` and use the binary with the arguments after the `--` to (de)compress the file.

## information
A simple file compressor using Huffman encoding.

Should you use this? No, it is inefficient, single threaded and full of bugs.
