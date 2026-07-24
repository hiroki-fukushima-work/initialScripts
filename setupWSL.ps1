<# =====================================================================
  setupWSL.ps1
  - WSLを有効化し、Ubuntu ディストリビューションを "DockerBase" という名前で
    インストールする
  実行要件:
    - 管理者権限で実行すること
    - 初回実行後、再起動が必要な場合がある
===================================================================== #>

# 管理者権限チェック
$isAdmin = (
  New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
  )
).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator
)

# 管理者でなければ再起動
if (-not $isAdmin) {
  Start-Process powershell `
    -Verb RunAs `
    -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
# 1. WSL オプション機能の有効化
# ---------------------------------------------------------------
Write-Host "[1/4] Windows Subsystem for Linux を有効化しています..."
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -ne "Enabled") {
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
  Write-Host "      有効化しました。"
}
else {
  Write-Host "      すでに有効化されています。"
}

# ---------------------------------------------------------------
# 2. 仮想マシンプラットフォームの有効化 (WSL2 に必要)
# ---------------------------------------------------------------
Write-Host "[2/4] 仮想マシンプラットフォームを有効化しています..."
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmFeature.State -ne "Enabled") {
  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
  Write-Host "      有効化しました。"
}
else {
  Write-Host "      すでに有効化されています。"
}

# ---------------------------------------------------------------
# 3. WSL の既定バージョンを 2 に設定
# ---------------------------------------------------------------
Write-Host "[3/4] WSL の既定バージョンを 2 に設定しています..."
wsl --set-default-version 2 | Out-Null
Write-Host "      完了。"

# ---------------------------------------------------------------
# 4. Ubuntu をインポートして "DockerBase" という名前で登録
# ---------------------------------------------------------------
Write-Host "[4/4] Ubuntu ディストリビューションを DockerBase としてインストールしています..."

$distroName = "DockerBase"
$existingList = wsl --list --quiet 2>$null

if ($existingList -match $distroName) {
  Write-Host "      ディストリビューション '$distroName' はすでに存在します。スキップします。"
}
else {
  # wsl --install で Ubuntu をインストール後、名前を変更する方式
  # (インターネット接続が必要)
  Write-Host "      Ubuntu をダウンロード・インストールします (しばらくお待ちください)..."

  # 一時的に "Ubuntu" としてインストール
  wsl --install --distribution Ubuntu --no-launch

  # インストールされた Ubuntu ディストリを DockerBase にエクスポート→インポートして名前変更
  $tempDir = Join-Path $env:TEMP "wsl_export"
  $exportFile = Join-Path $tempDir  "ubuntu_base.tar"
  $installDir = Join-Path $env:USERPROFILE "WSL\$distroName"

  New-Item -ItemType Directory -Force -Path $tempDir    | Out-Null
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null

  Write-Host "      Ubuntu を初期化しています..."
  # 初回起動して初期化 (root ユーザーで即終了)
  wsl --distribution Ubuntu --user root -- echo "init done"

  Write-Host "      エクスポートしています..."
  wsl --export Ubuntu $exportFile

  Write-Host "      '$distroName' としてインポートしています..."
  wsl --import $distroName $installDir $exportFile --version 2

  Write-Host "      元の Ubuntu ディストリビューションを削除しています..."
  wsl --unregister Ubuntu

  Remove-Item $exportFile -Force
  Remove-Item $tempDir    -Force -Recurse

  # ---------------------------------------------------------------
  # デフォルトユーザー (testuser) の作成とパスワード設定
  # ---------------------------------------------------------------
  $defaultUser = "testuser"
  $defaultPass = "testuser"

  Write-Host "      ユーザー '$defaultUser' を作成しています..."
  wsl --distribution $distroName --user root -- useradd -m -s /bin/bash $defaultUser
  wsl --distribution $distroName --user root -- bash -c "echo '${defaultUser}:${defaultPass}' | chpasswd"
  wsl --distribution $distroName --user root -- usermod -aG sudo $defaultUser

  # WSL 起動時のデフォルトユーザーを設定 (/etc/wsl.conf に書き込む)
  $wslConfContent = "[user]`ndefault=$defaultUser"
  wsl --distribution $distroName --user root -- bash -c "printf '[user]\ndefault=$defaultUser\n' > /etc/wsl.conf"

  # WSL 起動時のデフォルトユーザーを設定 (/etc/wsl.conf に書き込む)
  # ※ 上の行と重複しているため削除済み (wsl.conf はすでに書き込み済み)

  # ---------------------------------------------------------------
  # setupLinux.sh を WSL 内にコピーして自動実行
  # ---------------------------------------------------------------
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $setupLinuxSh = Join-Path $scriptDir "setupLinux.sh"

  if (Test-Path $setupLinuxSh) {
    Write-Host "      setupLinux.sh を '$distroName' 内で実行しています..."

    # Windows パスを WSL パスに変換して内部にコピー
    $wslScriptPath = "/tmp/setupLinux.sh"
    $winPathForWsl = $setupLinuxSh -replace '\\', '/' -replace '^([A-Za-z]):', '/mnt/$1'.ToLower()
    # ドライブレター部分を小文字に変換して /mnt/<drive> 形式にする
    $driveLetter = $setupLinuxSh.Substring(0, 1).ToLower()
    $relativePath = ($setupLinuxSh.Substring(2) -replace '\\', '/')
    $wslSourcePath = "/mnt/${driveLetter}${relativePath}"

    wsl --distribution $distroName --user root -- bash -c "cp '$wslSourcePath' $wslScriptPath && chmod +x $wslScriptPath && bash $wslScriptPath"
    Write-Host "      setupLinux.sh の実行が完了しました。"
  }
  else {
    Write-Host "      [SKIP] setupLinux.sh が見つかりませんでした: $setupLinuxSh"
  }

  # 設定を反映させるため一度シャットダウン
  wsl --terminate $distroName

  Write-Host "      '$distroName' のインストールが完了しました。"
  Write-Host "      デフォルトユーザー : $defaultUser"
}

# ---------------------------------------------------------------
# 完了メッセージ
# ---------------------------------------------------------------
Write-Host ""
Write-Host "========================================================"
Write-Host "セットアップが完了しました。"
Write-Host "  ディストリビューション名 : $distroName"
Write-Host "  デフォルトユーザー       : testuser"
Write-Host "  起動コマンド             : wsl -d $distroName"
Write-Host ""
Write-Host "※ 機能の有効化直後は再起動が必要な場合があります。"
Write-Host "   再起動後に再度このスクリプトを実行してください。"
Write-Host "========================================================"

