param(
    [Parameter(Mandatory)] [string] $InputPath,
    [Parameter(Mandatory)] [string] $OutputPath
)

$ErrorActionPreference = "Stop"

[xml] $jacoco = Get-Content -LiteralPath $InputPath -Raw
$coverage = New-Object System.Xml.XmlDocument
$declaration = $coverage.CreateXmlDeclaration("1.0", "UTF-8", $null)
$coverage.AppendChild($declaration) | Out-Null
$root = $coverage.CreateElement("coverage")
$root.SetAttribute("version", "1")
$coverage.AppendChild($root) | Out-Null

foreach ($package in $jacoco.report.package) {
    $packagePath = ([string]$package.name).Replace(".", "/").TrimEnd("/")

    foreach ($sourceFile in $package.sourcefile) {
        $filePath = "$packagePath/$($sourceFile.name)"
        $file = $coverage.CreateElement("file")
        $file.SetAttribute("path", $filePath)

        foreach ($line in $sourceFile.line) {
            $coveredBranches = [int]$line.cb
            $missedBranches = [int]$line.mb
            $isCovered = [int]$line.ci -gt 0
            $lineElement = $coverage.CreateElement("lineToCover")
            $lineElement.SetAttribute("lineNumber", [string]$line.nr)
            $lineElement.SetAttribute("covered", $isCovered.ToString().ToLowerInvariant())

            if (($coveredBranches + $missedBranches) -gt 0) {
                $lineElement.SetAttribute("branchesToCover", [string]($coveredBranches + $missedBranches))
                $lineElement.SetAttribute("coveredBranches", [string]$coveredBranches)
            }

            $file.AppendChild($lineElement) | Out-Null
        }

        $root.AppendChild($file) | Out-Null
    }
}

$coverage.Save($OutputPath)
