# tzip
An extremely simple file compressor written in zig.

## Building
requirements: `zig` (I used 0.14)

To compile the program
```sh
zig build
```

To compress a file:
```sh
path/to/tz compress [file to compress] [output file]
```

To decompress a file:
```sh
path/to/tz decompress [compressed file]
```

By default, the path to `tz` is `./zig-out/bin/tz`

## information
A simple file compressor using Huffman encoding.

Should you use this? No, it is inefficient, single threaded and probably full of bugs.

## todo
- don't write usize to the file => compatible between 32 and 64 bit machines
- add async support
- add some other algorithms
    - which ones?
