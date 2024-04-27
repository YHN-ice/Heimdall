# Heimdall

A minimal SSH client for watch that could monitor server activity.

This project is a minimal SSH client designed to run on a watch device. It is built using the following libraries:
- [swift-nio-ssh](https://github.com/apple/swift-nio-ssh.git)
- [swift-crypto](https://github.com/apple/swift-crypto.git)

The user interface (UI) is intentionally kept simple for now. The primary purpose of this project is to get a elementary taste of Swift language[^1] and watchOS development. Nonetheless, it serves as a convenient tool for monitoring server Cpu usage. Additionally, with a minor modification, you can check if a long-running process has terminated, maybe due to out-of-memory (OOM) errors.

## Authentication
The client utilizes public key authentication with a single attempt mechanism. It does not validate the host key, therefore it is not recommended for production use at this stage. Key pairs are generated using CryptoKit and stored securely in the Keychain. The process for transforming keys from `SecKey` to the `ssh-keygen` format is inspired by [migueldeicaza/SwiftTermApp](https://github.com/migueldeicaza/SwiftTermApp.git).

## Command Execution
The client sends commands non-interactively through a one-time `ChildChannel` from [swift-nio-ssh](https://github.com/apple/swift-nio-ssh.git) and closes it shortly after. The `Process.exec()` method is used to execute commands, with the default command being:

``` shell
top -bn1 | grep "Cpu(s)" | awk '{print $8}'
```


This default command is intended to monitor the CPU usage of a server directly from your watch.

[^1]: A lot in common with Rust
