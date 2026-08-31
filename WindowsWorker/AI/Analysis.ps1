# ============================================================
# AI/Analysis.ps1 - Local rule-based explainer (always online-capable offline)
# ============================================================

function Invoke-LocalAIAnalysis {
    param(
        $Snapshot,
        $Findings,
        $Decision,
        $DoctorPanel
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $primary = if ($Findings -and @($Findings).Count -gt 0) { @($Findings)[0] } else { $null }

    if ($primary -and $primary.Severity -eq 'HEALTHY') {
        [void]$parts.Add('Node dang o trang thai on dinh. Rule engine khong yeu cau can thiep.')
    } elseif ($primary) {
        $know = Get-KnowledgeForFinding $primary
        [void]$parts.Add("Phat hien: [$($primary.Severity)] $($primary.RootCause) (confidence ~$($primary.Confidence)%).")
        if ($know) { [void]$parts.Add($know) }
    } else {
        [void]$parts.Add('Khong co finding noi bat tu rule engine.')
    }

    if ($Decision -and $Decision.Action -notin @('NONE', 'MONITOR', 'WAIT_MONITOR')) {
        [void]$parts.Add("De xuat cua Spider: $($Decision.Action) (Risk $($Decision.Risk), Mode $($Decision.Mode)).")
        if ($Decision.RequiresApproval) {
            [void]$parts.Add('Can phe duyet nguoi dung truoc khi thuc hien (Safety Policy).')
        } elseif ($Decision.AutoExecute) {
            [void]$parts.Add('Mode hien tai cho phep tu thuc hien action nay trong gioi han an toan.')
        }
    } elseif ($Decision -and $Decision.Action -eq 'WAIT_MONITOR') {
        [void]$parts.Add('Khuyen nghi theo doi them - chua can reset.')
    }

    if ($Decision -and $Decision.DependencyNote) {
        [void]$parts.Add("Dependency: $($Decision.DependencyNote)")
    }

    if ($DoctorPanel -and $DoctorPanel.Critical -gt 0) {
        $critNames = @($DoctorPanel.Results | Where-Object { $_.Status -eq 'CRITICAL' } | ForEach-Object { $_.Doctor })
        [void]$parts.Add("Doctor CRITICAL: $($critNames -join ', ').")
    }

    if ($Snapshot -and $Snapshot.Network -and -not $Snapshot.Network.Internet) {
        [void]$parts.Add('Luu y: mat Internet - uu tien sua mang, khong restart Node truoc.')
    }

    $text = ($parts -join ' ')
    $rec = if ($Decision) { $Decision.Action } else { 'NONE' }

    return [pscustomobject]@{
        Enabled          = $true
        Provider         = 'Local'
        Explanation      = $text
        Recommendation   = $rec
        ConfidenceBoost  = 0
        AdvisoryOnly     = $true
        SafetyBypass     = $false
    }
}
