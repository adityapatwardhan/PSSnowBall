using namespace Microsoft.ApplicationInsights
using namespace Microsoft.ApplicationInsights.DataContracts
using namespace Microsoft.ApplicationInsights.Extensibility

class AppInsightsTelemetry {
    [TelemetryClient] $TelemetryClient

    AppInsightsTelemetry([string] $InstrumentationKey) {
        [TelemetryConfiguration]::Active.InstrumentationKey = $InstrumentationKey
        [TelemetryConfiguration]::Active.TelemetryChannel.DeveloperMode = $true
        $this.TelemetryClient = [TelemetryClient]::new()
    }

    [void] TrackEvent([string] $EventName, [System.Collections.Generic.Dictionary[string, string]] $Properties, [System.Collections.Generic.Dictionary[string, double]] $Metrics) {
        $this.TelemetryClient.TrackEvent($EventName, $Properties, $Metrics)
    }
}

class PSSnowballRunConfig {
    [Int64] $MaximumIterationCount
    [Int64] $MaximumWarmupIterationCount
    [string] $RunId
    [bool] $IsEnabled
    [AppInsightsTelemetry] $AppInsightsTelemetry
    [System.Collections.Generic.Dictionary[string, string]] $RunEnvironment
    [string] $PwshPath
}

function Start-PSSnowballRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InstrumentationKey = "c4df244c-dc9e-4390-b07e-4192f2958769",
        [Parameter()] [UInt64] $MaximumIterationCount = 50,
        [Parameter()] [UInt64] $MaximumWarmupIterationCount = 5,
        [Parameter()] [string] $PwshPath
    )

    [PSSnowballRunConfig] $script:runConfig = [PSSnowballRunConfig]::new()
    ${script:runConfig}.MaximumIterationCount = $MaximumIterationCount
    ${script:runConfig}.MaximumWarmupIterationCount = $MaximumWarmupIterationCount
    ${script:runConfig}.RunId = New-Guid
    ${script:runConfig}.IsEnabled = $true
    ${script:runConfig}.AppInsightsTelemetry = [AppInsightsTelemetry]::new($InstrumentationKey)

    if ($PwshPath) {
        if (-not (Test-Path $PwshPath)) {
            throw "'$PwshPath' does not exist"
        }
        else {
            ${script:runConfig}.PwshPath = $PwshPath
        }
    }
    else {
        ${script:runConfig}.PwshPath = (Get-Command pwsh).Source
    }

    Write-Verbose -Verbose "Setting PwshPath as $(${script:runConfig}.PwshPath)"

    $sbPSInfo = { $PSVersionTable.PSVersion.ToString() ; if ($IsWindows) { "Windows"} elseif ($IsLinux) { "Linux" } else { "macOS" } }

    $psVersionInfo = & ${script:runConfig}.PwshPath -c $sbPSInfo
    $psVersionString = $psVersionInfo[0]
    $platform = $psVersionInfo[1]

    ${script:runConfig}.RunEnvironment = [System.Collections.Generic.Dictionary[string, string]]::new()
    ${script:runConfig}.RunEnvironment.Add('PSVersion', $psVersionString)
    ${script:runConfig}.RunEnvironment.Add('RunId', ${script:runConfig}.RunId)
    ${script:runConfig}.RunEnvironment.Add('Platform', $platform)

    Write-Verbose ("Started new run with id {0} and iteration count as {1}, warmup iteration count as {2}" -f ${script:runConfig}.RunId, ${script:runConfig}.MaximumIterationCount, ${script:runConfig}.MaximumWarmupIterationCount)
}

function Stop-PSSnowballRun {
    [CmdletBinding()]
    param(
    )

    ${script:runConfig}.IsEnabled = $false
    Write-Verbose ("Stopped run with id {0}" -f ${script:runConfig}.RunId)
}

function Test-IsRunEnabled {
    if (-not ${script:runConfig}.IsEnabled) {
        throw "Run not active, please run Start-PSSnowballRun"
    }
}

function Invoke-PSSnowballTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TestName,
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock,
        [Parameter()] [switch] $SkipUpload
    )

    Test-IsRunEnabled

    Write-Verbose "Started new test '$TestName'"

    $iterationMax = ${script:runConfig}.MaximumIterationCount
    $iterationWarmup = ${script:runConfig}.MaximumWarmupIterationCount

    $testScriptBlock = @"

`$null = Measure-Command { for(`$iteration = 0; `$iteration -lt $iterationWarmup; `$iteration++) { $ScriptBlock }}

`$currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
`$preTestProcessorTime = `$currentProcess.TotalProcessorTime.TotalMilliseconds

`$measurement = Measure-Command { for(`$iteration = 0; `$iteration -lt $iterationMax; `$iteration++) { $ScriptBlock }}

`$currentProcess.Refresh()
`$postTestProcessorTime = `$currentProcess.TotalProcessorTime.TotalMilliseconds
`$diffProcessorTime = `$postTestProcessorTime - `$preTestProcessorTime

`$avgDuration = `$measurement.TotalMilliseconds / $iterationMax
`$avgProcessorTime = `$diffProcessorTime / $iterationMax

`$avgDuration
`$avgProcessorTime
"@

    Write-Verbose "Test Script $testScriptBlock"

    $testOutput = & (${script:runConfig}.PwshPath) -c $testScriptBlock

    Write-Verbose "Ending test"

    Write-Verbose "`$testOutput = $testOutput"

    $avgDuration = [double]::Parse($testOutput[0])
    $avgProcessorTime = [double]::Parse($testOutput[1])

    $metrics = [System.Collections.Generic.Dictionary[string, double]]::new()
    $metrics.Add('AvgDurationMilliSeconds', $avgDuration)
    $metrics.Add('AvgProcessorTimeMilliSeconds', $avgProcessorTime)

    Write-Verbose "Starting upload"

    if (-not $SkipUpload) {
        ${script:runConfig}.AppInsightsTelemetry.TrackEvent($TestName, ${script:runConfig}.RunEnvironment, $metrics)
    }

    Write-Verbose "Return object"

    [PSCustomObject]@{
        RunId                        = ${script:runConfig}.RunId
        TestName                     = $TestName
        PSVersion                    = ${script:runConfig}.RunEnvironment['PSVersion']
        Platform                     = ${script:runConfig}.RunEnvironment['Platform']
        AvgDurationMilliSeconds      = $avgDuration
        AvgProcessorTimeMilliSeconds = $avgProcessorTime
    }

    Write-Verbose "Return object sent"
}
