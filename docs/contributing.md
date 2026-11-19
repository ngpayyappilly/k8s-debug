# Contributing

The source is at [github.com/ngpayyappilly/k8s-debug](https://github.com/ngpayyappilly/k8s-debug). Changes go
through pull requests to `main`.

## Add or change a tool

1. Add the package to the `apt-get install` list in the `Dockerfile` (or, for a standalone binary, add a pinned,
   **checksum-verified** download step like the existing ones).
2. Add the command name to the `TOOLS` list in `scripts/smoke-test.sh`.
3. Document it: add a `## \`toolname\`` section to the matching page under `docs/tools/`, with the package, the
   permissions it needs, and examples for Kubernetes situations.
4. Add it to the tables in `docs/index.md`, `docs/tools/index.md` and the banner in `motd.txt` if it is
   important enough to advertise.
5. Run the checks (below) and open a PR.

The documentation check fails the build if a tool in the smoke test has no section, so docs cannot silently fall
behind the image.

## Run the checks locally

```sh
docker build -t k8s-debug:dev .
scripts/smoke-test.sh k8s-debug:dev      # every tool exists and binaries run
scripts/check-docs.sh                    # every tool is documented

pip install -r docs/requirements.txt
mkdocs serve                              # live preview at http://127.0.0.1:8000
mkdocs build --strict                     # what CI runs; broken links fail
```

Pull requests also run `hadolint`, `shellcheck` and `actionlint`, and build and smoke-test the image on both
amd64 and arm64.

## Writing documentation

- Say **what the tool is for** in Kubernetes terms before listing flags.
- Every example should be something you have run. State the permission it needs.
- Prefer tested facts over general knowledge. If behaviour depends on the cluster, runtime or kubectl version,
  say so.
- Use `ghcr.io/ngpayyappilly/k8s-debug:latest` in examples, and placeholders such as `<pod>` for things the
  reader must replace.

## Releases

Releases are cut by pushing a version tag:

```sh
git tag v1.2.3 && git push origin v1.2.3
```

The publish workflow builds both platforms and pushes `1.2.3`, `1.2`, `1` and `latest`. Pre-release tags such as
`v1.3.0-rc.1` publish only that exact tag. Pushes to `main` publish `edge` and `sha-<commit>`.
The documentation site is rebuilt and deployed from `main` whenever `docs/` or `mkdocs.yml` changes.

## Extend the image for your own needs

If your platform needs tools that are not here (a JDK, `py-spy`, a database client), build on top:

```dockerfile
FROM ghcr.io/ngpayyappilly/k8s-debug:1.2.3

RUN apt-get update \
 && apt-get install -y --no-install-recommends redis-tools postgresql-client \
 && rm -rf /var/lib/apt/lists/*

COPY team-aliases.sh /etc/team-aliases.sh
RUN echo '. /etc/team-aliases.sh' >> /root/.bashrc
```

Pin the base to an exact version so your image changes only when you choose.
