param ( [switch]$noPublish )
$mName = "Microsoft.PowerShell.KubeCtl"
$packageInfo = Import-PowerShellDataFile "$PWD/${mName}.psd1"
$version = $packageInfo.moduleversion
$npkgName = "${mName}.${version}.nupkg"

$packageLocation = [System.IO.Path]::Combine("$PWD","..", "out","$mName","$version")
$experimentalDir = Join-Path $packageLocation experimental

# This should make the dirs that we need
if (!(Test-Path $packageLocation)) { New-Item -ItemType Directory $experimentalDir -Force}

$mFiles = "Microsoft.PowerShell.KubeCtl.Format.ps1xml",
    "Microsoft.PowerShell.KubeCtl.psd1",
    "Microsoft.PowerShell.KubeCtl.psm1",
    "ResourceConfiguration.json"
$eFiles = "KubeHelpParser.psm1"

foreach ( $f in $mFiles ) {
    Copy-Item $f $packageLocation
}

foreach ($f in $eFiles) {
    Copy-Item "experimental/$f" $experimentalDir
}

if ( $noPublish ) {
    return
}

$repoName = [guid]::newguid().ToString().Replace("-","")
$repoLoc = Join-Path ([io.path]::GetTempPath()) $repoName
$npkgPath = Join-Path $repoLoc $npkgName
try {
    $null = New-Item -ItemType Directory $repoLoc
    Register-PSRepository -name $repoName -SourceLocation $repoLoc
    Publish-Module -Path $packageLocation -Repository $repoName
    Copy-Item -Path $npkgPath -Destination $PWD
    "Package is: $npkgName"
}
finally {
    Unregister-PSRepository -Name $repoName -ErrorAction ignore
    Remove-Item -Recurse $repoLoc -ErrorAction ignore
}
