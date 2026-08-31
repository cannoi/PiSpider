# PiSpider Hybrid Core (SoloHost)

Dashboard for PiSpider on SoloHost. Windows Worker stays on the Node PC.

## Publish

```bash
git init
git add .
git commit -m "PiSpider Hybrid Core 1.0.0"
git branch -M main
git remote add origin https://github.com/YOUR_ORG/pispider-hybrid-core.git
git push -u origin main
```

GitHub Actions builds `ghcr.io/YOUR_ORG/pispider-hybrid-core:latest`.

In SoloHost `docker-compose.yml` and `config.json`, replace `YOUR_ORG`.

## Local image build

```bash
docker build -t pispider-hybrid-core:1.0.0 .
```

## Run (the 2 SoloHost files)

```bash
docker compose up -d
# http://SOLOHOST_IP:18770
```
