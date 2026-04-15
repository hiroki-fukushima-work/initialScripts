# 初期環境構築スクリプト

function getEnvironment() {
    # 環境変数を読み直す
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

$rubyIinstallList = @{
	"asciidoctor" = $false
	"asciidoctor-pdf" = $false
	"asciidoctor-pdf-cjk" = $false
	"asciidoctor-diagram" = $false
	"coderay" = $false
}

$chocoIinstallList = @{
	"7zip" = $false
	#"JDK8" = $false
	#"OpenJDK" = $false
	"temurin17" = $false
	"python" = $false
	"ruby" = $false
	"strawberryperl" = $false
	"git" = $false
	"tortoisegit" = $false
	"plantuml" = $false
	"graphviz" = $false
	"vscode" = $false
	"winmerge" = $false
	"teraterm" = $false
    "vscode-drawio" = $false
    "drawio" = $false
    "visualstudio2022buildtools" = $false
    "cmake" = $false
}
$vscodeExtensionIinstallList = @{
	"ms-ceintl.vscode-language-pack-ja" = $false
	"ms-python.python" = $false
	"vscjava.vscode-java-pack" = $false
	"jebbs.plantuml" = $false
	"asciidoctor.asciidoctor-vscode" = $false
	"ms-vscode.powershell" = $false
	"hediet.vscode-drawio" = $false
	"ms-vscode.cpptools" = $false
	"ms-vscode.cmake-tools" = $false
	"josetr.cmake-language-support-vscode" = $false
	"ms-vscode.cpptools-extension-pack" = $false
}

# Chocolateyのインストール
# https://chocolatey.org/install ここに従う

try {
    choco -v $_ -match '\d.\d.\d'
    choco upgrade all -y
}
catch {
    # インストールされていないのでインストールする
    Set-ExecutionPolicy Bypass -Scope Process -Force; 
   [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
   iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# chocolateyにインストールされていないパッケージをインストールする
$packages = choco list
foreach ($line in $packages) {
    $packageName = $line.Split(" ")[0].Trim()
    if ($chocoIinstallList.ContainsKey($packageName)) {
        $chocoIinstallList[$packageName] = $true
    }
}

foreach ($key in $chocoIinstallList.Keys) {
    $value = $chocoIinstallList[$key]
    if (-not $value) {
        choco install $key -y
        getEnvironment
    }
}

# Rubyにインストールされていないパッケージをインストールする
$packages = gem list
foreach ($line in $packages) {
    $packageName = $line.Split(" ")[0].Trim()
    if ($rubyIinstallList.ContainsKey($packageName)) {
        $rubyIinstallList[$packageName] = $true
    }
}

foreach ($key in $rubyIinstallList.Keys) {
    $value = $rubyIinstallList[$key]
    if (-not $value) {
        gem install $key
        getEnvironment
    }
}

# VSCodeの拡張機能をインストールする
$packages = code --list-extensions
foreach ($line in $packages) {
    $packageName = $line.Split(" ")[0].Trim()
    if ($vscodeExtensionIinstallList.ContainsKey($packageName)) {
        $vscodeExtensionIinstallList[$packageName] = $true
    }
}

foreach ($key in $vscodeExtensionIinstallList.Keys) {
    $value = $vscodeExtensionIinstallList[$key]
    if (-not $value) {
        code --install-extension  $key
    }
}
getEnvironment

