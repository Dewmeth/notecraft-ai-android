# NoteCraft AI: build an actual Android APK in GitHub Actions.
# Requirement: Windows PowerShell, Git, GitHub CLI (gh), a GitHub account.
# Run from this folder with: powershell -ExecutionPolicy Bypass -File .\BUILD_APK_ON_GITHUB.ps1
# The script creates an isolated PRIVATE repository and does not edit any existing repos.
param([string]$RepositoryName = 'notecraft-ai-android')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Check-Tool([string]$name, [string]$help) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "$name not found. $help"
  }
}

try {
  Check-Tool 'git' 'Install Git: https://git-scm.com/downloads'
  Check-Tool 'gh' 'Install GitHub CLI: https://cli.github.com/ (or run: winget install --id GitHub.cli)'
  & gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'Sign in to GitHub (opens an interactive browser login)...' -ForegroundColor Yellow
    & gh auth login --web --git-protocol https
    if ($LASTEXITCODE -ne 0) { throw 'GitHub login failed.' }
  }
  $owner = (& gh api user --jq '.login').Trim()
  if (-not $owner) { throw 'Unable to get GitHub username.' }
  $full = "$owner/$RepositoryName"
  Write-Host "Building NoteCraft in the PRIVATE repo $full" -ForegroundColor Cyan

  # Do not mutate an existing unrelated repository. Stop if the target exists.
  & gh repo view $full --json name 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    throw "The repo $full already exists. Re-run with -RepositoryName another-unique-name. Nothing was pushed."
  }
  if (Test-Path '.git') {
    throw 'This folder already contains Git history. Extract a fresh project ZIP to a new folder before using this script.'
  }
  & git init -b main
  if ($LASTEXITCODE -ne 0) { throw 'Could not initialize git.' }
  & git add -A
  if ($LASTEXITCODE -ne 0) { throw 'Could not stage project files.' }
  # Only temporary commit identity; does not change global Git configuration.
  & git -c "user.name=$owner" -c "user.email=$owner@users.noreply.github.com" commit -m 'Initial NoteCraft AI Flutter source and Android APK build'
  if ($LASTEXITCODE -ne 0) { throw 'Could not commit files.' }
  & gh repo create $full --private --source . --remote origin --push
  if ($LASTEXITCODE -ne 0) { throw 'Could not create and push the private repository.' }

  # Initial push invokes the workflow automatically. Run it manually as a fallback.
  Start-Sleep -Seconds 6
  $runsJson = & gh run list --repo $full --workflow 'Build Android APK' --branch main --limit 1 --json databaseId,status,conclusion
  $runs = $runsJson | ConvertFrom-Json
  if (-not $runs -or $runs.Count -eq 0) {
    & gh workflow run build-android-apk.yml --repo $full --ref main
    if ($LASTEXITCODE -ne 0) { throw 'Could not start the build workflow.' }
    Start-Sleep -Seconds 8
    $runsJson = & gh run list --repo $full --workflow 'Build Android APK' --branch main --limit 1 --json databaseId,status,conclusion
    $runs = $runsJson | ConvertFrom-Json
  }
  $runId = @($runs)[0].databaseId
  if (-not $runId) { throw "No APK build run found. Visit https://github.com/$full/actions" }
  Write-Host "Following Android APK build #$runId ..." -ForegroundColor Cyan
  & gh run watch $runId --repo $full --exit-status
  if ($LASTEXITCODE -ne 0) { throw "APK build failed. See logs at https://github.com/$full/actions/runs/$runId" }
  $outDir = Join-Path $PSScriptRoot 'APK_OUTPUT'
  New-Item -Force -ItemType Directory -Path $outDir | Out-Null
  & gh run download $runId --repo $full --name NoteCraft-AI-Android-APK --dir $outDir
  if ($LASTEXITCODE -ne 0) { throw 'The APK artifact could not be downloaded.' }
  $apk = Join-Path $outDir 'app-debug.apk'
  if (-not (Test-Path $apk)) { throw 'Android build reported success but output APK was not found.' }
  Copy-Item $apk (Join-Path $PSScriptRoot 'NoteCraft_AI.apk') -Force
  Write-Host "SUCCESS: $(Join-Path $PSScriptRoot 'NoteCraft_AI.apk')" -ForegroundColor Green
  Write-Host 'Transfer NoteCraft_AI.apk to your Android phone and open it to install.'
} catch {
  Write-Host "BUILD ERROR: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'If the build failed, share the GitHub Actions log for troubleshooting.'
  exit 1
}
