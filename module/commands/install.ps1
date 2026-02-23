# jdm - commands/install.ps1
# Orchestrates the full install flow

. "$PSScriptRoot\..\core\winget.ps1"
. "$PSScriptRoot\..\core\registry.ps1"
. "$PSScriptRoot\..\core\symlink.ps1"

function Invoke-Install {
    param(
        [Parameter(Mandatory)] [string] $UserInput
    )

    Write-Title "jdm install $UserInput"
    Write-Host ""

    # Step 1: Build search query
    $query = Build-Query -UserQuery $UserInput
    $results = Search-Winget -Query $query

    if ($results.Count -eq 0) {
        Write-Fail "No packages found for '$UserInput'. Check the name and try again."
        Write-Host ""
        Write-Host "  Examples:" -ForegroundColor Gray
        Write-Host "    jdm install temurin.21" -ForegroundColor Gray
        Write-Host "    jdm install corretto.17" -ForegroundColor Gray
        Write-Host "    jdm install azul.21" -ForegroundColor Gray
        return
    }

    # Step 2: Filter to JDK only
    $jdkResults = Filter-JDK -Results $results

    if ($jdkResults.Count -eq 0) {
        Write-Fail "No JDK packages found for '$UserInput'. Only JDK is supported."
        return
    }

    # Step 3: Let user pick if multiple results
    $selected = Select-Result -Results $jdkResults

    if (-not $selected) {
        Write-Step "Installation cancelled."
        return
    }

    # Step 4: Build registry key and check if already installed
    $key = Get-RegistryKey -Result $selected

    if (Test-VersionInstalled -Key $key) {
        Write-Host ""
        Write-Host "  [!] '$key' is already installed." -ForegroundColor Yellow
        $confirm = Read-Host "  Reinstall? (y/n)"
        if ($confirm -ne "y") {
            Write-Step "Skipping install."
            return
        }
    }

    # Step 5: Confirm with user before installing
    Write-Host ""
    Write-Host "  Package : $($selected.Name)" -ForegroundColor White
    Write-Host "  ID      : $($selected.Id)"   -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "  Proceed with install? (y/n)"
    if ($confirm -ne "y") {
        Write-Step "Installation cancelled."
        return
    }

    # Step 6: Build install path
    $installBase = "$env:USERPROFILE\.jdks\$key"

    # Step 7: Run winget install
    Write-Host ""
    $success = Install-WithWinget -Id $selected.Id -TargetPath $installBase

    if (-not $success) {
        Write-Fail "Installation failed. Please try again."
        return
    }

    # Step 8: Find the actual JDK root (vendor may add subfolders)
    Write-Step "Locating java.exe..."
    $javaExe = Get-ChildItem -Path $installBase -Filter "java.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $javaExe) {
        Write-Fail "Could not find java.exe inside $installBase"
        Write-Fail "The JDK may not have installed correctly."
        return
    }

    # The real JDK root is the parent of the bin folder
    $realPath = $javaExe.Directory.Parent.FullName
    Write-Ok "Found JDK root at: $realPath"

    # Step 9: Update registry with real path
    $vendor = Get-VendorFromId  -Id $selected.Id
    $version = Get-VersionFromId -Id $selected.Id

    $registered = Add-Version `
        -Key         $key `
        -Result      $selected `
        -InstallPath $realPath `
        -Vendor      $vendor `
        -Version     $version

    if (-not $registered) {
        Write-Fail "Failed to update registry."
        return
    }

    # Step 10: Update symlink if this should be current
    $current = Get-CurrentVersion
    $shouldSwitch = $false

    if (-not $current) {
        $shouldSwitch = $true
    }
    else {
        Write-Host ""
        $switchAnswer = Read-Host "  Set '$key' as current version? (y/n)"
        $shouldSwitch = ($switchAnswer -eq "y")
    }

    if ($shouldSwitch) {
        $switched = Switch-Version -TargetPath $realPath
        if ($switched) {
            Set-CurrentVersion -Key $key | Out-Null
        }
    }

    # Done
    Write-Host ""
    Write-Host "  [OK] Installed : $key" -ForegroundColor Green
    Write-Host "  [OK] Path      : $realPath" -ForegroundColor Green

    if ($shouldSwitch) {
        Write-Host "  [OK] Active    : $key (current)" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Open a new terminal and run: java -version" -ForegroundColor Cyan
    }
    else {
        Write-Host ""
        Write-Host "  To activate: jdm use $key" -ForegroundColor Cyan
    }

    Write-Host ""
}

function Select-Result {
    param(
        [Parameter(Mandatory)] [array] $Results
    )

    if ($Results.Count -eq 1) {
        return $Results[0]
    }

    Write-Host ""
    Write-Host "  Found multiple matches:" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $Results.Count; $i++) {
        $r = $Results[$i]
        Write-Host "    $($i + 1). $($r.Name)" -ForegroundColor White
        Write-Host "       $($r.Id)" -ForegroundColor Gray
    }

    Write-Host ""
    $choice = Read-Host "  Which one? (1-$($Results.Count)) or q to cancel"

    if ($choice -eq "q") { return $null }

    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $Results.Count) {
        Write-Fail "Invalid choice."
        return $null
    }

    return $Results[$index]
}
