# nerdctl

Download latest `nerdctl` release
```bash
wget https://github.com/containerd/nerdctl/releases/download/v2.2.2/nerdctl-full-2.2.2-linux-amd64.tar.gz
```

Extract to /usr/local
```bash
sudo tar -C /usr/local -xzf nerdctl-full-2.2.2-linux-amd64.tar.gz
```

Verify
```bash
nerdctl --version
```


---


### CentOS 9

Install `gzip`:
```bash
sudo dnf install -y gzip --disableexcludes=all
```
