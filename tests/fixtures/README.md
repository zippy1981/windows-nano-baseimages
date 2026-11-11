# Test fixtures

| File | What it is | Source and licence |
| --- | --- | --- |
| `zip-deflate64.zip` | A zip whose entries are Deflate64 (method 9): the 30-byte file `xyzxyzxyzxyzxyzxyzxyzxyzxyzxyz/abcabcabcabcabcabcabcabcabcabc.txt` (contents `abc` × 10), two symlinks and a directory. SHA-256 `2c22fc01537c6cb6b5310c91a12b6096ef20c48a09451ace57396919ce0fa3ec`. `scripts/Test-LibarchivePackage.ps1` extracts the file from it, from a file and from a pipe (issue #7). | `libarchive/test/test_read_format_zip_deflate64.zip.uu` from [libarchive/libarchive#2806](https://github.com/libarchive/libarchive/pull/2806), uudecoded. libarchive's tests are BSD-2-Clause. |
