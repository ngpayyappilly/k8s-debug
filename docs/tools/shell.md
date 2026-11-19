# Shell and files

The environment you work in, plus general-purpose utilities.

## `bash`

**Package:** `bash`, `bash-completion` · **Needs:** nothing special

The default shell (it is the image's entrypoint). The configuration in `/root/.bashrc` gives you:

| Feature | Detail |
|---|---|
| Banner | A summary of the tools and `--target` tips, shown once per interactive shell |
| Prompt | `[debug] <pod-hostname>:<dir> #` |
| `k` | Alias for `kubectl`, with tab completion |
| `troot <pid>` | Prints `/proc/<pid>/root`, the target container's filesystem: `ls $(troot 1)/etc` |
| `ll` | `ls -alF` |
| History | 5000 lines, kept for the session only (the container's disk is ephemeral) |
| `vim` | Alias for `vi` |

Tab completion works for `kubectl` and for commands and file names. Run one-off commands without a shell by
passing them to `kubectl debug`:

```sh
kubectl debug -it <pod> --image=ghcr.io/ngpayyappilly/k8s-debug:latest --target=<c> -- tcpdump -i any -nn -p port 53
```

!!! tip "Capturing the output of a short command"
    If a command finishes before `kubectl debug` attaches, you see no output. The output is still saved:
    `kubectl logs <pod> -c <debug-container-name>`. Give the container a name with `--container=<name>` so
    you can find it.

## `vi`

**Package:** `vim-tiny` · **Needs:** nothing special

A small `vi`. The `vim` command is an alias to it. Syntax highlighting and plugins are not included, which is
fine for editing a config file. `i` to insert, `Esc` then `:wq` to save and quit, `:q!` to quit without saving.

Remember that the debug container's filesystem is separate from the app's. To edit a file the **app** reads, you
can go through `/proc/<pid>/root/...`, but only if that path is on a writable volume, and changes are lost when the
pod restarts.

## `nano`

**Package:** `nano` · **Needs:** nothing special

An easier editor if you do not know `vi`. `Ctrl-O` saves, `Ctrl-X` exits.

## `less`

**Package:** `less` · **Needs:** nothing special

A pager for long output and files.

```sh
less /proc/$P/root/var/log/app.log      # read the app's log file
dmesg -T | less
less +F /proc/$P/root/var/log/app.log   # follow like `tail -f`; Ctrl-C to stop following, F to resume
```

Inside `less`: `/text` searches, `n` repeats, `G` goes to the end, `q` quits.

## `file`

**Package:** `file` · **Needs:** nothing special

Identifies what a file is, based on its contents. Useful for telling a script from a binary, or checking
architecture and linkage before you debug it.

```sh
file /proc/$P/root/usr/local/bin/app
```

```text
ELF 64-bit LSB executable, ARM aarch64, ... statically linked, stripped
```

*Stripped* means no symbols (poor `gdb` stack traces). *Statically linked* means [`ltrace`](processes.md#ltrace)
will not work on it. If the architecture differs from the node's, you have the wrong image.

## `tree`

**Package:** `tree` · **Needs:** nothing special

```sh
tree -L 2 /proc/$P/root/app            # two levels deep
tree -a -L 3 /proc/$P/root/etc/nginx
```

## `unzip`

**Package:** `unzip` · **Needs:** nothing special

```sh
unzip -l artifact.jar                  # list the contents of a jar/zip without extracting
unzip -p app.jar META-INF/MANIFEST.MF  # print one file
```

`tar`, `gzip` and `bzip2` are part of the base system. See also [`xz`](#xz).

## `xz`

**Package:** `xz-utils` · **Needs:** nothing special

```sh
xz -dc dump.sql.xz | head              # read a compressed file without unpacking
tar -xJf bundle.tar.xz
```

## `git`

**Package:** `git` · **Needs:** nothing special

Clone configuration repositories, compare manifests, or bisect a config change from inside the cluster
network, for example to reach an internal Git server the cluster can see but your laptop cannot.

```sh
git clone https://git.internal.example.com/team/config.git
git diff --no-index /proc/$P/root/etc/app/config.yaml ./config.yaml
```

`git diff --no-index` compares any two files, whether or not they are in a repository.

## `ssh`

**Package:** `openssh-client` · **Needs:** nothing special

An SSH client, including `scp` and `ssh-keygen`. Use it to test connectivity to a bastion or SFTP server from the
pod's network position.

```sh
ssh -v -o BatchMode=yes -o ConnectTimeout=5 user@host true     # verbose connect test, no prompts
scp user@host:/path/file .
ssh-keyscan -t ed25519 host                                    # fetch a host key
```

Never bake private keys into images, and avoid typing passphrases in a recorded session.

## `gpg`

**Package:** `gnupg` · **Needs:** nothing special

Verify signatures and decrypt files, for example release artifacts or encrypted secrets.

```sh
gpg --verify artifact.tar.gz.asc artifact.tar.gz
gpg --list-keys
```

## `python3`

**Package:** `python3` · **Needs:** nothing special

The Python 3 standard library, with no extra packages. Handy for quick scripts when no other tool does the job.

```sh
# Serve this container's directory over HTTP, to copy a file to another pod or laptop quickly
python3 -m http.server 8000

# TCP reachability check with a timeout, anywhere `nc` is blocked
python3 -c "import socket; socket.create_connection(('my-svc', 5432), 3); print('open')"

# Pretty-print JSON
curl -s localhost:8080/status | python3 -m json.tool

# Resolve a name through the pod's resolver, exactly as a Python app would
python3 -c "import socket; print(socket.getaddrinfo('my-svc.my-ns', 80))"
```

!!! note "Also in the base system"
    `ca-certificates` provides the trusted CA bundle, so `curl` and `openssl` trust public sites. To trust an
    internal CA, copy it to `/usr/local/share/ca-certificates/` with a `.crt` extension and run
    `update-ca-certificates`. The standard coreutils (`base64`, `sha256sum`, `dd`, `timeout`, `watch`, `sort`,
    `awk`, `sed`, `grep`) are all present.
