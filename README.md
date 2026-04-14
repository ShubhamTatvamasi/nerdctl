# nerdctl

Download latest `nerdctl` release
```bash
curl -LO https://github.com/containerd/nerdctl/releases/latest/download/nerdctl-full-$(uname -s)-$(uname -m).tar.gz
```

Extract to /usr/local
```bash
sudo tar -C /usr/local -xzf nerdctl-full-*.tar.gz
```

Verify
```bash
nerdctl --version
```
