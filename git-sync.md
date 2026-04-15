# git-sync

Start `git-sync` container:
```bash
nerdctl run --rm -it \
  --entrypoint bash \
  registry.k8s.io/git-sync/git-sync:v4.6.0
```

Warm up network before `git clone`:
```bash
curl -m 1 https://github.com || true && \
  git clone https://github.com/ShubhamTatvamasi/fluxcd.git
```
