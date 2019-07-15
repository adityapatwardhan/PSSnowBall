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
}

function Start-PSSnowballRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InstrumentationKey = "c4df244c-dc9e-4390-b07e-4192f2958769",
        [Parameter()] [UInt64] $MaximumIterationCount = 25,
        [Parameter()] [UInt64] $MaximumWarmupIterationCount = 5
    )

    [PSSnowballRunConfig] $script:runConfig = [PSSnowballRunConfig]::new()
    ${script:runConfig}.MaximumIterationCount = $MaximumIterationCount
    ${script:runConfig}.MaximumWarmupIterationCount = $MaximumWarmupIterationCount
    ${script:runConfig}.RunId = New-Guid
    ${script:runConfig}.IsEnabled = $true
    ${script:runConfig}.AppInsightsTelemetry = [AppInsightsTelemetry]::new($InstrumentationKey)

    $psVersionString = $PSVersionTable.PSVersion.ToString()
    $platform = $PSVersionTable.Platform.ToString()
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

    ${script:runConfig}.$IsEnabled = $false
    Write-Verbose ("Stopped run with id {}" -f ${script:runConfig}.RunId)
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
    $testScriptBlockWarmup = [scriptblock]::Create("for(`$iteration = 0; `$iteration -lt $iterationWarmup; `$iteration++) { $ScriptBlock }")
    $testScriptBlock = [scriptblock]::Create("for(`$iteration = 0; `$iteration -lt $iterationMax; `$iteration++) { $ScriptBlock }")

    Write-Verbose "Starting warmup"
    Write-Verbose "Test Script $testScriptBlockWarmup"

    $null = Measure-Command -Expression $testScriptBlockWarmup

    Write-Verbose "Ending warmup"

    Write-Verbose "Starting test"
    Write-Verbose "Test Script $testScriptBlock"

    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $preTestProcessorTime = $currentProcess.TotalProcessorTime.TotalMilliseconds

    $measurement = Measure-Command -Expression $testScriptBlock

    $currentProcess.Refresh()
    $postTestProcessorTime = $currentProcess.TotalProcessorTime.TotalMilliseconds
    $diffProcessorTime = $postTestProcessorTime - $preTestProcessorTime

    Write-Verbose "Ending test"

    $avgDuration = $measurement.TotalMilliseconds / $iterationMax
    $avgProcessorTime = $diffProcessorTime / $iterationMax

    $metrics = [System.Collections.Generic.Dictionary[string, double]]::new()
    $metrics.Add('AvgDurationMilliSeconds', $avgDuration)
    $metrics.Add('AvgProcessorTimeMilliSeconds', $avgProcessorTime)

    Write-Verbose "Starting upload"

    if (-not $SkipUpload) {
        ${script:runConfig}.AppInsightsTelemetry.TrackEvent($TestName, ${script:runConfig}.RunEnvironment, $metrics)
    }

    [PSCustomObject]@{
        RunId                        = ${script:runConfig}.RunId
        TestName                     = $TestName
        PSVersion                    = ${script:runConfig}.RunEnvironment['PSVersion']
        Platform                     = ${script:runConfig}.RunEnvironment['Platform']
        AvgDurationMilliSeconds      = $avgDuration
        AvgProcessorTimeMilliSeconds = $avgProcessorTime
    }
}
