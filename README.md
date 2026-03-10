# Codex Quota Dashboard Kit

OpenClaw + Codex OAuth profillerini görsel dashboard'da gösterir.

## Özellikler
- Profil bazlı quota görünümü
- Manual `Refresh` butonu (cron ile sürekli sorgu yok)
- `flock` kilidi ile güvenli collector
- Ayrı agent ile güvenli auth-order probing (opsiyonel, önerilir)
- Tailscale üzerinden uzaktan erişim

## Kurulum
```bash
git clone <REPO_URL>
cd quota-dashboard-kit
bash install.sh
```

Kurulum sonrası çıktıdaki linki aç.

## Kullanım
- Dashboard: `http://<tailscale-ip>:8787`
- Refresh: UI'dan `🔄 Refresh`

## Komutlar
```bash
bash scripts/start.sh
bash scripts/stop.sh
bash scripts/codex-quota-collector.sh
bash scripts/codex-quota-report.sh --json | jq .
```

## Konfigürasyon
`.env` dosyasından:
- `AGENT_ID=quota`
- `CREATE_AGENT=1`
- `PROVIDER=openai-codex`
- `PORT=8787`
- `BIND_HOST=auto`

## Kaldırma
```bash
bash uninstall.sh
```

Bu sadece dashboard process + cron satırını kaldırır; dosyaları silmez.
