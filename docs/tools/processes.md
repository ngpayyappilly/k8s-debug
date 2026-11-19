# Processes and system

Find out what the app is doing, what it is waiting on, and what the kernel thinks about it.

!!! important "Start with `--target`"
    Without `--target=<container>` you share only the pod's **network**. Add it and the target container's
    processes appear in `ps`, and you can reach its filesystem, environment and limits through `/proc`:

    ```sh
    P=$(pgrep -o <app-name>)            # or just 1, the app is usually PID 1
    ls /proc/$P/root/                    # its filesystem
    tr '\0' '\n' < /proc/$P/environ      # its environment variables
    cat /proc/$P/cmdline | tr '\0' ' '   # how it was started
    cat /proc/$P/limits                  # ulimits (open files, processes)
    ls /proc/$P/fd | wc -l               # how many file descriptors it holds
    cat /proc/$P/root/sys/fs/cgroup/cpu.max /proc/$P/root/sys/fs/cgroup/memory.max   # its limits
    ```

    The helper `troot <pid>` prints `/proc/<pid>/root`. Reading another user's process needs `SYS_PTRACE`,
    which the default profile has.

!!! note "User names come from this image"
    `ps` and `ls -l` translate numeric IDs using **this image's** `/etc/passwd`, not the target's. A
    process running as UID 101 may be shown as `tcpdump`. Use numeric IDs (`ps -eo pid,uid,comm`) when it
    matters.

## `ps`

**Package:** `procps` · **Needs:** nothing special (`--target` to see the app)

```sh
ps auxf                                                    # all processes, as a tree
ps -eo pid,ppid,uid,stat,%cpu,%mem,rss,etime,cmd           # custom columns
ps -eo pid,%cpu,%mem,cmd --sort=-%cpu | head               # top CPU users
ps -eo pid,rss,cmd --sort=-rss | head                      # top memory users
ps -o pid,nlwp,cmd -p <pid>                                # thread count of one process
ps -eo stat,pid,cmd | awk '$1 ~ /^Z/'                      # zombie processes
```

`STAT` letters: `R` running, `S` sleeping, `D` uninterruptible I/O wait (often a stuck disk or NFS mount),
`Z` zombie (the parent never reaped it).

## `pgrep`

**Package:** `procps` · **Needs:** nothing special

```sh
pgrep -a nginx             # PIDs and command lines matching a name
pgrep -o java              # the oldest match, usually the main process
pgrep -f 'my-app --port'   # match the full command line
```

`pkill` from the same package sends signals by name. Be careful: a signal reaches the **target** container's
processes too.

## `top`

**Package:** `procps` · **Needs:** nothing special

```sh
top                    # interactive; press 1 for per-CPU, H for threads, c for full command
top -b -n 1 | head -20     # one snapshot, handy for logs
top -H -p <pid>            # threads of one process
```

!!! warning "CPU and memory totals are the node's"
    `top`, `free` and `/proc/meminfo` report the **node's** resources, not the container's limits. To know
    what the app may use, read its cgroup (see the box at the top of this page).

## `free`

**Package:** `procps` · **Needs:** nothing special

```sh
free -m
```

Shows node memory (see the warning under [`top`](#top)). For the container's real limit and usage, look in its
cgroup:

```sh
cat /proc/$P/root/sys/fs/cgroup/memory.max       # the limit ("max" means unlimited)
cat /proc/$P/root/sys/fs/cgroup/memory.current   # current use
cat /proc/$P/root/sys/fs/cgroup/memory.events    # oom and oom_kill counters
```

## `vmstat`

**Package:** `procps` · **Needs:** nothing special

```sh
vmstat 1 5
```

Five one-second samples of node-wide activity. Read `r` (runnable processes, compare to CPU count), `b`
(blocked), `si`/`so` (swapping), `wa` (CPU time waiting on I/O).

## `htop`

**Package:** `htop` · **Needs:** nothing special

A friendlier interactive process viewer. Needs a terminal, so use `kubectl debug -it`.

```sh
htop
htop -p <pid>,<pid>        # only these processes
```

`F5` toggles tree view, `F4` filters, `F2` setup (add columns such as `IO_RATE`), `t` toggles tree, `H` hides
user threads.

## `lsof`

**Package:** `lsof` · **Needs:** `SYS_PTRACE` to see other users' processes

Lists open files, and in Unix everything is a file: sockets, pipes, devices, directories.

```sh
lsof -p <pid>                              # everything one process has open
lsof -nP -iTCP -sTCP:LISTEN                # listening TCP sockets with process
lsof -nP -i :8080                          # who uses port 8080?
lsof -nP -iTCP -sTCP:ESTABLISHED -a -p <pid>   # its live connections
lsof +L1                                   # deleted files that are still open (disk space not freed)
lsof -p <pid> | wc -l                      # rough descriptor count; compare with `cat /proc/<pid>/limits`
```

A steadily growing descriptor count is a leak. Many entries of one type (for example `sock`) show what kind.
`lsof +L1` finds the classic "disk is full but I deleted the big file" case: a process still holds it open.

## `fuser`

**Package:** `psmisc` · **Needs:** `SYS_PTRACE` for other users' processes

Shows which processes use a file, directory or port.

```sh
fuser -v 8080/tcp          # who is listening on 8080?
fuser -vm /proc/$P/root/data   # who is using this mount?
```

`psmisc` also provides `killall` and [`pstree`](#pstree).

## `pstree`

**Package:** `psmisc` · **Needs:** nothing special

```sh
pstree -p            # process tree with PIDs
pstree -ap <pid>     # a subtree with command-line arguments
```

## `pidstat`

**Package:** `sysstat` · **Needs:** nothing special

Per-process statistics over time, which `top` cannot give you in a script-friendly form.

```sh
pidstat -u -p <pid> 1 5            # CPU of one process, 5 samples
pidstat -r -p <pid> 1 5            # memory: page faults, RSS
pidstat -d -p <pid> 1 5            # disk I/O per process
pidstat -w -p <pid> 1 5            # context switches (many "nvcswch" = CPU contention)
pidstat -t -p <pid> 1 5            # per-thread
```

`pidstat -d` is the practical stand-in for [`iotop`](#iotop) in containers.

## `iostat`

**Package:** `sysstat` · **Needs:** nothing special

Disk I/O for the whole node (block devices).

```sh
iostat -xz 1 5
```

`%util` near 100 and a high `await` mean the disk is saturated. Remember you see **node** devices, not only the
pod's volumes.

## `mpstat`

**Package:** `sysstat` · **Needs:** nothing special

Per-CPU utilisation.

```sh
mpstat -P ALL 1 5
```

One CPU at 100% while the rest idle points at a single-threaded bottleneck. High `%steal` in a VM means the
hypervisor is taking CPU away. High `%iowait` means processes are waiting for disk.

## `iotop`

**Package:** `iotop-c` · **Needs:** `sysadmin` profile, and the kernel setting `task_delayacct`

Live per-process disk I/O.

```sh
iotop -oPa               # only active processes, accumulated
iotop -b -n 1 -o         # batch mode, one snapshot
```

It frequently prints `Warning: task_delayacct is 0`. Enable it on the node with
`echo 1 > /proc/sys/kernel/task_delayacct` (or boot with `delayacct`), or use [`pidstat -d`](#pidstat) instead,
which needs neither.

## `strace`

**Package:** `strace` · **Needs:** `SYS_PTRACE` (default profile)

Prints the system calls a process makes. When an app hangs, fails mysteriously or is slow, this shows what it
is asking the kernel to do and what the kernel answered.

```sh
strace -f -tt -T -p <pid>                       # follow threads, timestamps, time per call
strace -f -p <pid> -e trace=network             # only network calls
strace -f -p <pid> -e trace=file                # only file-related calls (finds missing config files: ENOENT)
strace -f -p <pid> -e trace=openat,connect -s 256   # specific calls, longer strings
strace -c -f -p <pid>                           # summary table of calls, errors and time; Ctrl-C to print
strace -f -o /tmp/strace.out -p <pid>           # write to a file
```

Common findings: `connect(...) = -1 ECONNREFUSED`, `openat(...) = -1 ENOENT` for a missing file,
a thread stuck in `futex(...)` (waiting on a lock) or `read(...)` / `epoll_wait(...)` (waiting for I/O or events).

!!! warning "It slows the target down"
    `strace` stops the process at every system call. On a busy production process this can cause timeouts and
    failed health probes. Filter with `-e trace=...`, use `-c`, attach briefly, or prefer
    [`bpftrace`](#bpftrace) for high-rate processes.

## `ltrace`

**Package:** `ltrace` · **Needs:** `SYS_PTRACE`

Like `strace`, but for **library** calls (for example `malloc`, `getaddrinfo`, `SSL_read`).

```sh
ltrace -f -p <pid> -e getaddrinfo      # which hostnames is it resolving?
ltrace -c -p <pid>                      # call summary
```

Works for dynamically linked programs using glibc. It does not work on statically linked binaries, and Go
programs do not use the C library for most work, so for those use [`strace`](#strace).

## `gdb`

**Package:** `gdb` · **Needs:** `SYS_PTRACE`

The GNU debugger. For a live process you most often want a stack dump of every thread.

```sh
# One-shot stack of all threads, then detach (the process resumes)
gdb -p <pid> -batch -ex 'thread apply all bt' -ex detach

# Interactive
gdb -p <pid>
(gdb) info threads
(gdb) thread apply all bt
(gdb) detach
(gdb) quit

# Analyse a core file with the binary that produced it
gdb /proc/$P/root/usr/local/bin/app /path/to/core
```

!!! warning "Attaching pauses the process"
    The process is stopped while `gdb` is attached. Detach promptly or a liveness probe may kill the pod. Stack
    traces are readable only if the binary has symbols. Stripped binaries show addresses.

## `bpftrace`

**Package:** `bpftrace` · **Needs:** the `sysadmin` profile (eBPF needs `SYS_ADMIN`/`BPF`/`PERFMON`) and a
kernel with eBPF and BTF

A scripting language for eBPF: low-overhead tracing of the kernel and applications without stopping them.

```sh
# Check it works
bpftrace -e 'BEGIN { printf("ok\n"); exit(); }'

# Every file opened, with the process that opened it
bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'

# Count system calls per process for 10 seconds
bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); } interval:s:10 { exit(); }'

# New TCP connections (kernel function probe)
bpftrace -e 'kprobe:tcp_connect { printf("%s connecting\n", comm); }'

# List available probes
bpftrace -l 'tracepoint:syscalls:sys_enter_*' | head
```

Requires a privileged container, so use `--profile=sysadmin`. Many managed clusters and hardened namespaces
forbid that. If it fails with permission errors, [`strace`](#strace) is the fallback.

## `nsenter`

**Package:** `util-linux` · **Needs:** `sysadmin` profile (`SYS_ADMIN` and `SYS_PTRACE`)

Runs a command inside another process's namespaces. Most useful in a **node** session, where you can step into
a container or into the node itself.

```sh
# From a node debug session: become the node (PID 1's namespaces) and use its own tools
nsenter -t 1 -m -u -i -n -p -- systemctl status kubelet
nsenter -t 1 -m -u -i -n -p -- journalctl -u kubelet --since '10 min ago'

# Run a command in a container's network namespace (find the PID on the node first)
nsenter -t <container-pid> -n ip addr
```

In an ordinary pod session you already share the pod's network namespace, so you rarely need it.

## `lsns`

**Package:** `util-linux` · **Needs:** nothing special

Lists namespaces and which process owns each, for understanding what you share with whom.

```sh
lsns
lsns -t net          # network namespaces only
```

If the pod and a process share a network namespace ID, they share an IP address.

## `findmnt`

**Package:** `util-linux` · **Needs:** nothing special

Shows mounts as a tree, with options. Good for checking whether a volume is mounted, read-only, or on the
right filesystem.

```sh
findmnt                                     # this container's mounts
findmnt -R /proc/$P/root                    # (node) mounts beneath a container root, if visible
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS /host/var/lib/kubelet/pods
```

For the **app's** view of mounts, read `cat /proc/$P/mountinfo`.

## `dmesg`

**Package:** `util-linux` · **Needs:** `sysadmin` profile (`SYSLOG` on many kernels)

The kernel ring buffer: OOM kills, hardware errors, filesystem errors, conntrack table messages, network
driver resets.

```sh
dmesg -T | tail -50                          # human-readable timestamps
dmesg -T | grep -i -E 'oom|killed process'   # OOM kills
dmesg -T | grep -i conntrack
```

An OOM kill here (`Out of memory: Killed process ...`) confirms a container exceeded its memory limit, whatever
the application logged.

## `lsmod`

**Package:** `kmod` · **Needs:** nothing special

Lists loaded kernel modules, read from `/proc/modules`.

```sh
lsmod | grep -E 'conntrack|ip_vs|overlay|wireguard|vxlan'
```

Check whether a module your CNI or `kube-proxy` mode needs (such as `nf_conntrack`, `ip_vs`, `vxlan`) is loaded.
Loading modules (`modprobe`) needs `sysadmin` and is rarely what you want in production.

## `lspci`

**Package:** `pciutils` · **Needs:** nothing special

Lists PCI devices. Mostly relevant on **node** sessions for GPU, SR-IOV or high-performance NIC problems.

```sh
lspci
lspci -k | grep -A3 -i -E 'ethernet|nvidia'     # devices with their kernel drivers
```
