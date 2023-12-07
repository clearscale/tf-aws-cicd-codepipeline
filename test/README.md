# Testing

This is the [terratest](https://terratest.gruntwork.io/docs/getting-started/quick-start/) directory which uses [Go](https://go.dev/doc/tutorial/getting-started) to write and perform tests.

```bash
go version go1.21.5 linux/amd64
```

## Setup

To initial terratest, install Go and then run the following commands:

```bash
cd test
go mod tidy
go test
```

For verbose output and custom timeout values use the `-v` and `-timeout` flags:

```bash
cd test
go test -v -timeout 30m
```

## Success Example

```bash
Destroy complete! Resources: 0 destroyed.
PASS
ok      github.com/clearscale/tf-context        88.727s
```
