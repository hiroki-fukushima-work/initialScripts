<# =====================================================================
  setupDev.ps1  (WinGet + PSGallery 版 / Chocolatey 非依存)
  - アプリ配布は WinGet に統一
  - RubyGems と VS Code 拡張もインストール
  - 再実行安全（idempotent）/ DryRun / Proxy / Export に対応
  - 既定では VS Code をデフォルト設定（scope 指定なし）で導入
  - Git の右クリック統合はデフォルト（変更しない）
  参考: WinGet 基本コマンド（Microsoft Learn）
        https://learn.microsoft.com/en-us/windows/wsl/basic-commands
===================================================================== #>

[CmdletBinding()]
param(
    # Machine or User（規定値：Machine。VS Code は scope 指定なし＝アプリ既定の挙動）
    [ValidateSet('Machine','User')]
    [string]$Scope = 'Machine',

    # 何をするかの予行演習（出力のみ／実行しない）
    [switch]$DryRun,

    # WinGet Export 出力パス（指定時のみ export 実行）
    [string]$ExportPath,

    # VSCode 拡張の導入をスキップ
    [switch]$NoVSCodeExtensions,

    # RubyGems の導入をスキップ
    [switch]$NoRubyGems,

    # WinGet の --proxy に渡す（http[s]://host:port）
    [string]$Proxy
)

# ---------------------------
# ユーティリティ
# ---------------------------
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level,
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts][$Level] $Message"
    switch ($Level) {
        'INFO'  { Write-Host $line -ForegroundColor Cyan }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error $Message }
        'DEBUG' { Write-Verbose $Message }
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandExists {
    param([Parameter(Mandatory=$true)][string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# VS Code CLI の取得（PATH未反映でも既定場所を試す）
function Get-CodeCmd {
    if (Test-CommandExists -Name 'code') { return 'code' }
    $cands = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    )
    foreach ($p in $cands) { if (Test-Path $p) { return $p } }
    return $null
}

# PATH 再読込（ユーザーさんの既存方針を踏襲）
function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH','User')
}

# ---------------------------
# WinGet 検査
# ---------------------------
function Ensure-WinGet {
    if (Test-CommandExists -Name 'winget') { return $true }
    Write-Log INFO "winget が見つかりません。App Installer（Microsoft Store）をインストールしてください。"
    # 基本コマンドや入手方法は Microsoft Learn の基本コマンド参照
    # https://learn.microsoft.com/en-us/windows/wsl/basic-commands
    return $false
}

# ---------------------------
# ZIP インストーラ
# ---------------------------
function Install-Apps-With-Zip {
    param(
        [Parameter(Mandatory=$true)][hashtable]$ZipMap,
        [Parameter(Mandatory=$true)][string]$ToolsDir,
        [switch]$DryRun
    )

    New-Item -ItemType Directory -Force $ToolsDir | Out-Null

    foreach ($name in $ZipMap.Keys) {
        $item = $ZipMap[$name]

        $zipUrl     = $item.ZipPath
        $folderName = $item.FolderName
        $exeName    = $item.ExeName

        $installDir = Join-Path $ToolsDir $folderName
        $zipFile    = Join-Path $env:TEMP "$folderName.zip"

        Write-Log INFO "ZIP check: $name"

        if ((Test-Path $installDir) -and ($exeName -and (Test-Path (Join-Path $installDir $exeName)))) {
            Write-Log INFO "ZIP Installed: $name - skip"
            continue
        }

        if ($DryRun) {
            Write-Log INFO "[DryRun] Download $zipUrl -> $zipFile"
            Write-Log INFO "[DryRun] Expand $zipFile -> $installDir"
            continue
        }

        try {
            Write-Log INFO "ZIP download: $name"
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing

            if (Test-Path $installDir) {
                Write-Log INFO "ZIP cleanup existing folder: $installDir"
                Remove-Item $installDir -Recurse -Force
            }

            Write-Log INFO "ZIP extract: $name"
            Expand-Archive -Path $zipFile -DestinationPath $installDir -Force

            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

            Write-Log INFO "ZIP install done: $name"
        }
        catch {
            Write-Log WARN "ZIP install failed: $name - $($_.Exception.Message)"
        }
    }
}

# ---------------------------
# WinGet インストーラ
# ---------------------------
function Install-Apps-With-WinGet {
    param(
        [Parameter(Mandatory=$true)][hashtable]$AppMap,     # 表示名→ID
        [hashtable]$OverrideMap,                            # ID→override 文字列
        [string]$Scope = 'Machine',
        [switch]$DryRun,
        [string]$Proxy,
        [switch]$UseWingetSourceOnly,                       # msstoreを避けたい環境で有効
        [switch]$WithVerboseWingetLogs                      # 詳細ログを採取したいときに指定
    )

    $scopeArg = @()
    if ($Scope -in @('Machine','User')) { $scopeArg = @('--scope', $Scope.ToLower()) }

    $proxyArg = @()
    if ($Proxy) { $proxyArg = @('--proxy', $Proxy) }

    $sourceArg = @()
    if ($UseWingetSourceOnly) { $sourceArg = @('--source','winget') }

    $wgLogArg = @()
    if ($WithVerboseWingetLogs) { $wgLogArg = @('--verbose-logs') }   # --open-logs は対話が必要なので常用は避ける

    # 共通フラグ
    $WG_ACCEPT = @('--accept-source-agreements','--accept-package-agreements')
    $WG_NONINT = @('--disable-interactivity')              # list/show/install すべてで付与
    $WG_SILENT = @('-h')                                   # install のみで付与

    $failed = @()

    # 公式リターンコード（よく使う分のみ）
    $NO_APPS_FOUND        = -1978335212 # 0x8A150014
    $DOWNLOAD_FAILED      = -1978335224 # 0x8A150008
    $NO_APPLICABLE        = -1978335216 # 0x8A150010

    # ユーティリティ: 数値を 0xXXXXXXXX に
    function To-Hex([int]$code) { ('0x{0:X8}' -f ([uint32]([int]$code))) }

    $total = $AppMap.Keys.Count
    $index = 0

    foreach ($name in $AppMap.Keys) {
        $index++
        $id = $AppMap[$name]
        Write-Log INFO ("[{0}/{1}] START check: {2} ({3})" -f $index, $total, $name, $id)


        # 既に入っているか？（list 前に必ず段階ログ）
        Write-Log INFO ("[{0}/{1}] phase=list: id={2}" -f $index, $total, $id)

        $LASTEXITCODE = 0
        # 出力本文で判定する（stderrは捨てる）
        $already = & winget list --id $id --exact `
                    --disable-interactivity `
                    --accept-source-agreements --accept-package-agreements `
                    @sourceArg 2>$null | Out-String
        $listCode = $LASTEXITCODE  # ← ここは「致命的エラー時の保険」としてだけ使う

        # 1) list 自体が失敗している（ネット断/内部例外など）ときだけコードで扱う
        if ($listCode -ne 0) {
            Write-Log WARN ("[{0}/{1}] list failed: dec={2}, id={3}" -f $index, $total, $listCode, $id)
            # ここで source update や再試行などの回復策を行い、ダメなら continue
            & winget source update --disable-interactivity --accept-source-agreements 2>$null | Out-Null
            # 必要なら winget show -e --id $id でIDの妥当性確認を出力ログに残す
            & winget show --id $id -e --disable-interactivity --accept-source-agreements @sourceArg 2>$null | Out-Null
            # （再試行の成否で分岐…）
        }

        # 2) exit code が 0 の場合は、本文で判定
        if ($already -match [regex]::Escape($id)) {
            Write-Log INFO ("[{0}/{1}] detected=installed: {2} -> skip" -f $index, $total, $name)
            continue
        }

        # 3) ここまで来たら「未インストール」とみなして install へ
        #Write-Log INFO ("[{0}/{1}] not-installed, go install: {2}" -f $index, $total, $name)

        $already = & winget list --id $id --exact `
                    --disable-interactivity `
                    --accept-source-agreements --accept-package-agreements `
                    @sourceArg 2>$null | Out-String

        if ($already -match [regex]::Escape($id)) {
            Write-Log INFO ("[{0}/{1}] detected=installed: {2} -> skip" -f $index, $total, $name)
            continue
        }

        Write-Log INFO ("[{0}/{1}] not-installed, go install: {2}" -f $index, $total, $name)
        

        # --- install 実行前ログ ---
        $args = @('install','--id',$id,'--exact') + $WG_SILENT + $WG_ACCEPT + $WG_NONINT + $scopeArg + $proxyArg + $sourceArg + $wgLogArg
        if ($OverrideMap.ContainsKey($id) -and $OverrideMap[$id]) {
            $args += @('--override', $OverrideMap[$id])
        }

        if ($DryRun) {
            Write-Log INFO ("[{0}/{1}] DRYRUN install: winget {2}" -f $index, $total, ($args -join ' '))
            continue
        }

        # （例：VS Code のロック回避）
        # Stop-Process -Name "Code" -Force -ErrorAction SilentlyContinue

        Write-Log INFO ("[{0}/{1}] phase=install: id={2}" -f $index, $total, $id)
        & winget @args
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            Write-Log WARN ("[{0}/{1}] install non-zero: app={2}, dec={3}, hex={4}" -f $index, $total, $name, $code, (To-Hex $code))
            $failed += $name
        } else {
            Write-Log INFO ("[{0}/{1}] install done: {2}" -f $index, $total, $name)
            Refresh-Path
        }
    }

    if ($failed.Count -gt 0) {
        Write-Log WARN ("FAILED apps: " + ($failed -join ', '))
        Write-Log INFO  ("Winget verbose logs (if enabled) are under: %LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir")
        # 上記のログディレクトリは公式トラブルシューティングに記載あり（--verbose-logs / --open-logs）[1](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)
    } else {
        Write-Log INFO ("All apps installed successfully.")
    }
}

# ---------------------------
# RubyGems インストーラ
# ---------------------------
function Install-RubyGems {
    param(
        [string[]]$Gems,
        [switch]$DryRun
    )
    if (-not (Test-CommandExists -Name 'gem')) {
        Write-Log WARN "Ruby (gem) が見つかりません。Ruby 本体の導入後に再実行してください。"
        return
    }
    foreach ($g in $Gems) {
        Write-Log INFO ("インストール: " + ($g))
        $has = gem list | Select-String -SimpleMatch "$g "
        if ($has) {
            Write-Log INFO "RubyGems Installed: $g - skip"
        } else {
            if ($DryRun) {
                Write-Log INFO "[DryRun] gem install $g"
            } else {
                Write-Log INFO "RubyGems Install: $g"
                gem install $g
            }
        }
    }
}

# ---------------------------
# VS Code 拡張 インストーラ
# ---------------------------
function Install-VSCodeExtensions {
    param(
        [string[]]$Extensions,
        [switch]$DryRun
    )
    $codeCmd = Get-CodeCmd
    if (-not $codeCmd) {
        Write-Log WARN "VS Code の CLI (code) が見つかりません。VS Code 導入直後はシェル再起動が必要な場合があります。"
        return
    }
    $installed = & $codeCmd --list-extensions 2>$null

    foreach ($ext in $Extensions) {
        Write-Log WARN ("インストール: " + ($ext))
        if ($installed -and ($installed -match [regex]::Escape($ext))) {
            Write-Log INFO "VSCode Ext Installed: $ext - skip"
        } else {
            if ($DryRun) {
                Write-Log INFO "[DryRun] $codeCmd --install-extension $ext"
            } else {
                Write-Log INFO "VSCode Ext Install: $ext"
                & $codeCmd --install-extension $ext
            }
        }
    }
}

# ---------------------------
# メイン
# ---------------------------
Write-Log INFO "セットアップ開始"

# スコープと権限
if ($Scope -eq 'Machine' -and -not (Test-Admin)) {
    Write-Log WARN "Machine スコープを指定しています。管理者 PowerShell を推奨します。"
}

# WinGet 確認
if (-not (Ensure-WinGet)) { 
    Write-Log ERROR "セットアップWinGetが使えません"
    exit 1 
}

# WinGet パッケージ一覧（表示名=>ID）
# ※ ID は環境で `winget show <name>` で確認可能
# 参考: Microsoft Learn（winget 基本コマンド、install/list/upgrade など）
$AppMap = @{
    '7-Zip'                    = '7zip.7zip'
    'Eclipse Temurin 17'       = 'EclipseAdoptium.Temurin.17.JDK'   # Java 17
    'Python 3'                 = 'Python.Python.3.13'
    'Ruby'                     = 'RubyInstallerTeam.RubyWithDevKit.3.4'
    'Strawberry Perl'          = 'StrawberryPerl.StrawberryPerl'
    'Git'                      = 'Git.Git'
    'TortoiseGit'              = 'TortoiseGit.TortoiseGit'
    'Graphviz'                 = 'Graphviz.Graphviz'
    'Visual Studio Code'       = 'Microsoft.VisualStudioCode'        # scope 指定なし（デフォルト）
    'WinMerge'                 = 'WinMerge.WinMerge'
    'Tera Term'                = 'TeraTermProject.teraterm'
    'CMake'                    = 'Kitware.CMake'
    'VS 2022 Build Tools'      = 'Microsoft.VisualStudio.2022.BuildTools'
    'draw.io Desktop'          = 'JGraph.Draw'
    'Sakura Editor'            = 'sakura-editor.sakura'
    'inkscape'                 = 'Inkscape.Inkscape'
}

# Zip Installer
$toolsDir = "C:\tools"

$ZipMap = @{
    "A5:SQL Mk-2" = @{
        ZipPath    = "https://a5m2.mmatsubara.com/downloads/A5M2.zip"
        FolderName = "A5M2"
        ExeName    = "A5M2.exe"
    }
}

New-Item -ItemType Directory -Force $toolsDir | Out-Null

Install-Apps-With-Zip -ZipMap $ZipMap -ToolsDir $toolsDir -DryRun:$DryRun

# 今回は override 未使用（デフォルト動作）
$OverrideMap = @{}

Write-Log INFO "Wingetでインストールするアプリ"
Install-Apps-With-WinGet -AppMap $AppMap -OverrideMap $OverrideMap -Scope $Scope -DryRun:$DryRun -Proxy $Proxy -UseWingetSourceOnly

# RubyGems（必要に応じて）
if (-not $NoRubyGems) {
    Write-Log INFO "Rubyをインストール"
    $RubyGems = @('asciidoctor','asciidoctor-pdf','asciidoctor-pdf-cjk','asciidoctor-diagram','coderay')
    Install-RubyGems -Gems $RubyGems -DryRun:$DryRun
}

Write-Log INFO "ZIPファイルをダウンロードしてインストールするアプリ"

# VS Code 拡張（必要に応じて）
if (-not $NoVSCodeExtensions) {
    Write-Log INFO " VS Code 拡張をインストール"
    $VSCodeExtensions = @(
        'ms-ceintl.vscode-language-pack-ja',
        'ms-python.python',
        'vscjava.vscode-java-pack',
        'jebbs.plantuml',
        'asciidoctor.asciidoctor-vscode',
        'ms-vscode.powershell',
        'hediet.vscode-drawio',
        'ms-vscode.cpptools',
        'ms-vscode.cmake-tools',
        'josetr.cmake-language-support-vscode',
        'ms-vscode.cpptools-extension-pack',
        # OpenAPI関連
        'Redocly.openapi-vs-code',
        '42Crunch.vscode-openapi'
    )
    Install-VSCodeExtensions -Extensions $VSCodeExtensions -DryRun:$DryRun
}

# （任意）PSGallery モジュールの雛形（使用時はコメント解除）
<# 参考: Install-Module (PowerShellGet)
try {
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        Update-Module PSScriptAnalyzer -Force
    } else {
        Install-Module PSScriptAnalyzer -Force -AcceptLicense
    }
} catch {
    Write-Log WARN "PSGallery からのモジュール導入に失敗: $($_.Exception.Message)"
}
#>

# （任意）WinGet スナップショット
if ($ExportPath) {
    if ($DryRun) {
        Write-Log INFO "[DryRun] winget export -o `"$ExportPath`" --include-versions --accept-source-agreements"
    } else {
        Write-Log INFO "WinGet スナップショットを書き出し: $ExportPath"
        winget export -o "$ExportPath" --include-versions --accept-source-agreements
        # 参考: export/import で構成の再現（Microsoft Learn）
        # https://learn.microsoft.com/en-us/windows/wsl/basic-commands
    }
}

Write-Log INFO "セットアップ完了（Scope=$Scope, DryRun=$($DryRun.IsPresent)）"
