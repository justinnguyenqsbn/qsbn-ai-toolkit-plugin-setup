# Install or update the qsbn skills in the current project, using EITHER the Claude Code plugin
# OR skills.sh (never both). Project scope only. Safe to re-run: installs when missing, updates
# when present.
#
# Usage:
#   .\setup.ps1 [-Method plugin|skills] [-Yes]
#   $env:QSBN_METHOD='plugin'; irm https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.ps1))) -Method plugin
#
# Run it from inside the project's git repo. Never calls `exit`, so it is safe under `iex`.
param(
    [ValidateSet('plugin', 'skills')]
    [string]$Method = $env:QSBN_METHOD,
    [switch]$Yes
)

function Invoke-QsbnSetup {
    param([string]$Method, [bool]$Yes)

    $MarketplaceRepo = 'justinnguyenqsbn/qsbn-ai-toolkit-plugin'
    $MarketplaceName = 'qsbn-ai-toolkit-plugin'
    $Plugin = 'qsbn@qsbn-ai-toolkit-plugin'
    $RepoUrl = 'https://github.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin'

    function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

    function Confirm-Qsbn($question) {
        if ($Yes) { return $true }
        return ((Read-Host "$question [y/N]") -match '^(y|yes)$')
    }

    function Get-PluginScopes {
        if (-not (Test-Cmd claude)) { return @() }
        $json = claude plugin list --json 2>$null | Out-String
        if (-not $json.Trim()) { return @() }
        @($json | ConvertFrom-Json | Where-Object { $_.id -eq $Plugin } |
            Where-Object { $_.scope -ne 'project' -or -not $_.projectPath -or
                ((Resolve-Path $_.projectPath -ErrorAction SilentlyContinue).Path -eq (Get-Location).Path) } |
            ForEach-Object { $_.scope })
    }

    # The skills are internal, so list/remove/add only see them with INSTALL_INTERNAL_SKILLS=1.
    function Invoke-Skills {
        param([string[]]$SkillsArgs)
        $env:INSTALL_INTERNAL_SKILLS = 1
        try { npx -y skills@latest $SkillsArgs } finally { Remove-Item Env:INSTALL_INTERNAL_SKILLS -ErrorAction SilentlyContinue }
    }

    function Get-InstalledSkills {
        if (-not (Test-Cmd npx)) { return @() }
        # Keep only the skill-name column (lines starting with qsbn-), after stripping colour codes.
        @(Invoke-Skills list 2>$null | Out-String | ForEach-Object { $_ -split "`r?`n" } |
            ForEach-Object { $_ -replace '\x1b\[[0-9;]*m', '' } |
            Where-Object { $_ -match '^qsbn-\S+' } |
            ForEach-Object { ($_ -split '\s+')[0] } | Sort-Object -Unique)
    }

    function Remove-InstalledSkills {
        $names = Get-InstalledSkills
        if (-not $names) { return }
        Write-Host 'Removing installed qsbn skills:'
        $names | ForEach-Object { Write-Host $_ }
        # npx can crash on exit on Windows after a successful run, so judge by the result.
        Invoke-Skills (@('remove') + $names + '-y') | Out-Host
        if (Get-InstalledSkills) { throw 'Removing the installed skills failed.' }
    }

    # --- Project root: everything is installed at project scope -----------------------------
    if (-not (Test-Cmd git)) { throw 'git not found.' }
    $root = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $root) { throw 'Not inside a git repository. cd into your project first.' }
    Set-Location $root
    Write-Host "Project: $root"

    # --- Pick a method ----------------------------------------------------------------------
    if (-not $Method) {
        Write-Host ''
        Write-Host 'How do you want to install the qsbn skills? Pick ONE - do not use both.'
        Write-Host '  1) Claude Code plugin  (recommended for Claude Code users)'
        Write-Host '  2) skills.sh           (for other agents, or to copy skills into the repo)'
        switch (Read-Host 'Choice [1/2]') {
            '1' { $Method = 'plugin' }
            '2' { $Method = 'skills' }
            default { throw 'Invalid choice.' }
        }
    }

    # --- Plugin -----------------------------------------------------------------------------
    if ($Method -eq 'plugin') {
        if (-not (Test-Cmd claude)) { throw 'claude CLI not found. Install Claude Code first.' }

        $existing = Get-InstalledSkills
        if ($existing) {
            Write-Warning 'qsbn skills are already installed through skills.sh in this project:'
            $existing | ForEach-Object { Write-Host $_ }
            Write-Warning 'Do NOT use both the plugin and skills.sh: every qsbn skill would be installed twice.'
            if (-not (Confirm-Qsbn 'Remove the skills.sh skills now?')) {
                throw 'Aborted. Remove them first with: npx skills remove <names>'
            }
            Remove-InstalledSkills
        }

        $scopes = Get-PluginScopes
        foreach ($scope in ($scopes | Where-Object { $_ -ne 'project' })) {
            Write-Warning "The plugin is installed at '$scope' scope. This setup is project-only."
            if (-not (Confirm-Qsbn "Uninstall the $scope-scope copy?")) {
                throw "Aborted. Run: claude plugin uninstall $Plugin -s $scope"
            }
            claude plugin uninstall $Plugin -s $scope
            if ($LASTEXITCODE -ne 0) { throw "Uninstalling the $scope-scope plugin failed." }
        }

        claude plugin marketplace add $MarketplaceRepo --scope project
        if ($LASTEXITCODE -ne 0) { Write-Host 'Marketplace already added, continuing.' }
        if ($scopes -contains 'project') {
            Write-Host 'Plugin already installed in this project - updating.'
            claude plugin marketplace update $MarketplaceName
            if ($LASTEXITCODE -ne 0) { throw 'Marketplace update failed.' }
            claude plugin update $Plugin -s project
        } else {
            claude plugin install $Plugin -s project
        }
        if ($LASTEXITCODE -ne 0) { throw 'Plugin install/update failed.' }
        Write-Host 'Done. Restart Claude Code (or run /reload-plugins) to load the skills.'
        return
    }

    # --- skills.sh --------------------------------------------------------------------------
    if (-not (Test-Cmd npx)) { throw 'npx not found. Install Node.js first.' }

    $pluginScopes = Get-PluginScopes
    if ($pluginScopes) {
        Write-Warning "The qsbn Claude Code plugin ($Plugin) is installed."
        Write-Warning 'Do NOT use both the plugin and skills.sh: every qsbn skill would be installed twice.'
        if (-not (Confirm-Qsbn 'Remove the plugin now?')) {
            throw "Aborted. Remove it first with: claude plugin uninstall $Plugin"
        }
        foreach ($scope in $pluginScopes) {
            claude plugin uninstall $Plugin -s $scope
            if ($LASTEXITCODE -ne 0) { throw "Uninstalling the $scope-scope plugin failed." }
        }
    }

    # Remove first so skills deleted upstream disappear and new ones are picked up.
    Remove-InstalledSkills
    # Project scope is the default: never pass -g.
    Invoke-Skills @('add', $RepoUrl) | Out-Host
    if (-not (Get-InstalledSkills)) { throw 'skills.sh install failed.' }
    Write-Host 'Done. Restart your agent session so the skills are picked up.'
}

Invoke-QsbnSetup -Method $Method -Yes $Yes.IsPresent
