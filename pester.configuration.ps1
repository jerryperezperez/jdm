# pester.configuration.ps1
# Pester v5 configuration file for jdm project

$config = New-PesterConfiguration

# -------------------------------------------------------
# Run settings
# -------------------------------------------------------
$config.Run.Path = './tests'          # folder where test files live
$config.Run.Exit = $true             # exit with non-zero code if tests fail (important for CI)

# -------------------------------------------------------
# Output settings
# -------------------------------------------------------
$config.Output.Verbosity = 'Detailed' # options: None, Normal, Detailed, Diagnostic

# -------------------------------------------------------
# Test results (JUnit XML for SonarCloud/GitHub Actions)
# -------------------------------------------------------
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'JUnitXml'
$config.TestResult.OutputPath = './coverage/test-results.xml'

# -------------------------------------------------------
# Code coverage (JaCoCo XML for SonarCloud/Coverage Gutters)
# -------------------------------------------------------
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './module'              # folder with your source files
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = './coverage/coverage.xml'
$config.CodeCoverage.CoveragePercentTarget = 80     # fail if coverage drops below 80%

return $config
