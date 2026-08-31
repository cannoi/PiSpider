# ============================================================
# AI/Knowledge.ps1 - Local knowledge for explanations (offline)
# ============================================================

function Get-SpiderAIConfig {
    $p = Join-Path $script:SpiderRoot 'AI\AI_Config.json'
    if (Test-Path $p) {
        try { return Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Get-LocalKnowledgeSnippets {
    return @{
        'RAM_USER_PRESSURE' = 'RAM cao do ung dung nguoi dung (Chrome/Edge...). CLEAN_RAM an toan, khong dung Node.'
        'RAM_CRITICAL_USER' = 'RAM rat cao do app nguoi dung. Can CLEAN_RAM som de tranh OOM anh huong Docker/WSL.'
        'RAM_WSL_DOCKER' = 'RAM cao chu yeu do vmmem/Docker - binh thuong khi Node chay. KHONG restart WSL/Docker chi vi RAM.'
        'DOCKER_ENGINE_DOWN' = 'Docker Engine down. Thu SOFT_DOCKER_RESTART truoc. Chi ORDERED_WSL khi Desktop da tat. Cam wsl --shutdown khi Docker Desktop con chay (de treo).'
        'PI_CONTAINER_DOWN' = 'Container Pi/Stellar khong Up trong khi Docker OK. RESTART_NODE. Khong can reset ca Docker neu Engine healthy.'
        'NETWORK_DOWN' = 'Mat Internet. Sua NETWORK_REPAIR truoc - khong restart Node/Docker khi mat mang (dependency).'
        'DNS_FAIL' = 'Internet con nhung DNS loi. DNS_REFRESH thuong du.'
        'DISK_CRITICAL' = 'O dia gan day. CLEAN_TEMP; neu van thap can xoa thu cong Docker data/log.'
        'DISK_LOW' = 'O dia thap. CLEAN_TEMP du de dem thoi gian.'
        'STELLAR_STALL' = 'Ledger/peers yeu. Uu tien WAIT_MONITOR neu mang OK - tranh reset som.'
        'STELLAR_STALL_CRITICAL' = 'Tre khoi lau: chi docker restart container (RESTART_NODE). Khong /reset full, khong wsl --shutdown. Neu Docker treo: reboot may.'
        'PORTS_CLOSED' = 'Port Pi local khong mo. FIREWALL_CHECK (can Admin).'
        'CONFIG_CHANGED' = 'Cau hinh doi so voi baseline - chi bao cao, khong tu sua.'
        'VIRTUALIZATION_OFF' = 'Virtualization tat trong BIOS. Spider KHONG tu sua BIOS - user bat VT-x/AMD-V thu cong.'
        'WSL_DOWN' = 'WSL/Docker loi. ORDERED: tat Docker Desktop -> wsl --shutdown -> mo lai Docker. Neu van hong: HOST_REBOOT (can approve).'
        'NODE_HEALTHY' = 'He thong on dinh. Khong can can thiep.'
        'CPU_HIGH' = 'CPU cao nhung Node van healthy - theo doi.'
        'CPU_CRITICAL' = 'CPU rat cao - MAINTENANCE_LIGHT co the giam app rac.'
    }
}

function Get-KnowledgeForFinding {
    param($Finding)
    if (-not $Finding) { return $null }
    $map = Get-LocalKnowledgeSnippets
    $id = [string]$Finding.Id
    if ($map.ContainsKey($id)) { return $map[$id] }
    return "Rule $($Finding.Id): $($Finding.RootCause) → Action $($Finding.Action) (Risk $($Finding.Risk))."
}


# Community-derived guidance (see Rules/CommunityPlaybook.json)
$script:SpiderCommunityHints = @{
    'SYNC_LAG' = 'Container restart only first. Long Catching up after upgrade can be normal.'
    'DOCKER_DOWN' = 'Soft Docker Desktop recycle; never wsl --shutdown while Desktop runs.'
    'ZERO_PEERS' = 'Firewall + ports first. Router forward 31401-31410 is manual for bonus.'
    'BONUS' = 'Uptime + Synced + open ports + supporting nodes. Avoid destructive volume wipe.'
}
