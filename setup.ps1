# Install or update the qsbn skills in the current project, using EITHER the Claude Code plugin
# OR plain files copied into the repo (never both). Project scope only. Safe to re-run: installs
# when missing, updates when present.
#
# Usage:
#   .\setup.ps1 [-Method plugin|files] [-Yes]
#   $env:QSBN_METHOD='plugin'; irm https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.ps1))) -Method plugin
#
# files: clones the toolkit to a temp folder, then copies skills\ to .agents\skills\ (linked into
# .claude\skills\) and commands\qsbn\ to .claude\commands\qsbn\. Commit those folders to share them.
# Run it from inside the project's git repo. Never calls `exit`, so it is safe under `iex`.
# No [ValidateSet] here: under `iex` the param block turns into variable attributes and an empty
# default would be rejected. The value is validated inside the function instead.
param(
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

    # Paths of a previous files install (also catches skills left behind by skills.sh).
    function Get-InstalledFiles {
        $paths = @()
        foreach ($pattern in '.agents/skills/qsbn-*', '.claude/skills/qsbn-*', '.claude/commands/qsbn') {
            $paths += @(Get-Item -Path $pattern -Force -ErrorAction SilentlyContinue)
        }
        $paths
    }

    # A junction/symlink is deleted as a link only - never recursed into its target.
    function Remove-Qsbn($item) {
        if ($item.LinkType) { [System.IO.Directory]::Delete($item.FullName, $false) }
        else { Remove-Item -LiteralPath $item.FullName -Recurse -Force }
    }

    function Remove-InstalledFiles {
        $items = @(Get-InstalledFiles)
        if (-not $items) { return }
        Write-Host 'Removing previously installed qsbn files:'
        $items | ForEach-Object { Write-Host (Resolve-Path -LiteralPath $_.FullName -Relative) }
        # .claude first so links go before their targets.
        $items | Sort-Object { -not ($_.FullName -match '[\\/]\.claude[\\/]') } | ForEach-Object { Remove-Qsbn $_ }
    }

    # --- Project root: everything is installed at project scope -----------------------------
    if (-not (Test-Cmd git)) { throw 'git not found.' }
    $root = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $root) { throw 'Not inside a git repository. cd into your project first.' }
    Set-Location $root
    Write-Host "Project: $root"

    # --- Pick a method ----------------------------------------------------------------------
    if ($Method -eq 'skills') { $Method = 'files' }
    if (-not $Method) {
        Write-Host ''
        Write-Host 'How do you want to install the qsbn skills? Pick ONE - do not use both.'
        Write-Host '  1) Claude Code plugin  (recommended for Claude Code users)'
        Write-Host '  2) Files in this repo  (skills + /qsbn:* commands copied in, shareable through git)'
        switch (Read-Host 'Choice [1/2]') {
            '1' { $Method = 'plugin' }
            '2' { $Method = 'files' }
            default { throw 'Invalid choice.' }
        }
    }

    if ($Method -notin 'plugin', 'files') { throw "Invalid method '$Method' (use plugin or files)." }

    # --- Plugin -----------------------------------------------------------------------------
    if ($Method -eq 'plugin') {
        if (-not (Test-Cmd claude)) { throw 'claude CLI not found. Install Claude Code first.' }

        $existing = @(Get-InstalledFiles)
        if ($existing) {
            Write-Warning 'qsbn files are already installed in this project:'
            $existing | ForEach-Object { Write-Host (Resolve-Path -LiteralPath $_.FullName -Relative) }
            Write-Warning 'Do NOT use both the plugin and the files: every qsbn skill and command would be installed twice.'
            if (-not (Confirm-Qsbn 'Remove the installed files now?')) {
                throw 'Aborted. Delete those paths first.'
            }
            Remove-InstalledFiles
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

    # --- Files ------------------------------------------------------------------------------
    $pluginScopes = Get-PluginScopes
    if ($pluginScopes) {
        Write-Warning "The qsbn Claude Code plugin ($Plugin) is installed."
        Write-Warning 'Do NOT use both the plugin and the files: every qsbn skill and command would be installed twice.'
        if (-not (Confirm-Qsbn 'Remove the plugin now?')) {
            throw "Aborted. Remove it first with: claude plugin uninstall $Plugin"
        }
        foreach ($scope in $pluginScopes) {
            claude plugin uninstall $Plugin -s $scope
            if ($LASTEXITCODE -ne 0) { throw "Uninstalling the $scope-scope plugin failed." }
        }
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("qsbn-setup-" + [guid]::NewGuid().ToString('N'))
    try {
        Write-Host "Cloning $RepoUrl ..."
        git clone --depth 1 -q $RepoUrl (Join-Path $tmp 'repo')
        if ($LASTEXITCODE -ne 0) { throw "Could not clone $RepoUrl. Check your GitHub access to it." }
        $src = Join-Path $tmp 'repo'
        if (-not (Test-Path -LiteralPath (Join-Path $src 'skills'))) { throw 'The cloned repo has no skills/ folder.' }

        # Remove first so skills deleted upstream disappear and new ones are picked up.
        Remove-InstalledFiles
        New-Item -ItemType Directory -Force -Path '.agents/skills', '.claude/skills', '.claude/commands/qsbn' | Out-Null

        $count = 0
        foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $src 'skills') -Directory) {
            if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md'))) { continue }
            if ($dir.Name -notlike 'qsbn-*') { Write-Host "Skipping '$($dir.Name)' (name must start with qsbn-)."; continue }
            $real = Join-Path (Get-Location).Path ".agents/skills/$($dir.Name)"
            $link = Join-Path (Get-Location).Path ".claude/skills/$($dir.Name)"
            Copy-Item -LiteralPath $dir.FullName -Destination $real -Recurse -Force
            # A junction needs no admin rights on Windows (a symlink would). If linking fails for any
            # reason, fall back to a plain copy.
            try {
                if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
                    New-Item -ItemType Junction -Path $link -Target $real -ErrorAction Stop | Out-Null
                } else {
                    New-Item -ItemType SymbolicLink -Path $link -Target "../../.agents/skills/$($dir.Name)" -ErrorAction Stop | Out-Null
                }
            } catch {
                if (Test-Path -LiteralPath $link) { Remove-Qsbn (Get-Item -LiteralPath $link -Force) }
                Copy-Item -LiteralPath $dir.FullName -Destination $link -Recurse -Force
            }
            $count++
        }
        if ($count -eq 0) { throw 'No skills found in the cloned repo.' }

        $commands = Join-Path $src 'commands/qsbn'
        if (Test-Path -LiteralPath $commands) {
            Copy-Item -Path (Join-Path $commands '*.md') -Destination '.claude/commands/qsbn' -Force
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            # git marks pack files read-only, so -Force is needed.
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Installed $count skills into .agents/skills (linked from .claude/skills) and the /qsbn:* commands into .claude/commands/qsbn."
    Write-Host 'Done. Restart your agent session so they are picked up. Commit .agents/ and .claude/ to share them with your team.'
}

Invoke-QsbnSetup -Method $Method -Yes $Yes.IsPresent
