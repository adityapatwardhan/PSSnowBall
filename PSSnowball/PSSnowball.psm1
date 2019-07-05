using namespace Microsoft.ApplicationInsights
using namespace Microsoft.ApplicationInsights.DataContracts
using namespace Microsoft.ApplicationInsights.Extensibility

class AppInsightsTelemetry
{
    [TelemetryClient] $TelemetryClient

    AppInsightsTelemetry([string] $InstrumentationKey)
    {
        [TelemetryConfiguration]::Active.InstrumentationKey = $InstrumentationKey
        [TelemetryConfiguration]::Active.TelemetryChannel.DeveloperMode = $true
        $this.TelemetryClient = [TelemetryClient]::new()
    }

    [void] TrackEvent([string] $EventName, [System.Collections.Generic.Dictionary[string,string]] $Properties, [System.Collections.Generic.Dictionary[string, double]] $Metrics)
    {
        $this.TelemetryClient.TrackEvent($EventName, $Properties, $Metrics)
    }
}

class PSSnowballRunConfig
{
    [Int64] $MaximumIterationCount
    [string] $RunId
    [bool] $IsEnabled
    [AppInsightsTelemetry] $AppInsightsTelemetry
}

[PSSnowballRunConfig] $script:runConfig = [PSSnowballRunConfig]::new()

function Start-PSSnowballRun
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InstrumentationKey = "c4df244c-dc9e-4390-b07e-4192f2958769",
        [Parameter()] [UInt64] $MaximumIterationCount = 25
    )

    ${script:runConfig}.MaximumIterationCount = $MaximumIterationCount
    ${script:runConfig}.RunId = New-Guid
    ${script:runConfig}.IsEnabled = $true
    ${script:runConfig}.AppInsightsTelemetry = [AppInsightsTelemetry]::new($InstrumentationKey)

    Write-Verbose ("Started new run with id {0} and iteration count as {1}" -f ${script:runConfig}.RunId, ${script:runConfig}.MaximumIterationCount)
}

function Stop-PSSnowballRun
{
    [CmdletBinding()]
    param(
    )

    ${script:runConfig}.$IsEnabled = $false
    Write-Verbose ("Stopped run with id {}" -f ${script:runConfig}.RunId)
}

function Test-IsRunEnabled
{
    if (-not ${script:runConfig}.IsEnabled)
    {
        throw "Run not active, please run Start-PSSnowballRun"
    }
}

function Invoke-PSSnowballTest
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TestName,
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock
    )

    Test-IsRunEnabled

    Write-Verbose "Started new test '$TestName'"

    $iterationMax = ${script:runConfig}.MaximumIterationCount
    $testScriptBlock = [scriptblock]::Create("for(`$iteration = 0; `$iteration -lt $iterationMax; `$iteration++) { & $ScriptBlock }")

    Write-Verbose "Test Script $testScriptBlock"

    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $preTestProcessorTime = $currentProcess.TotalProcessorTime.TotalMilliseconds

    $measurement = Measure-Command -Expression $testScriptBlock

    $currentProcess.Refresh()
    $postTestProcessorTime = $currentProcess.TotalProcessorTime.TotalMilliseconds
    $diffProcessorTime = $postTestProcessorTime - $preTestProcessorTime

    $psVersionString = $PSVersionTable.PSVersion.ToString()

    $properties = [System.Collections.Generic.Dictionary[string, string]]::new()
    $properties.Add('PSVersion', $psVersionString)
    $properties.Add('RunId', ${script:runConfig}.RunId)
    $properties.Add('TestName', $TestName)

    $avgDuration = $measurement.TotalMilliseconds / $iterationMax
    $avgProcessorTime = $diffProcessorTime / $iterationMax

    $metrics = [System.Collections.Generic.Dictionary[string, double]]::new()
    $metrics.Add('AvgDurationMilliSeconds', $avgDuration)
    $metrics.Add('AvgProcessorTimeMilliSeconds', $avgProcessorTime)

    ${script:runConfig}.AppInsightsTelemetry.TrackEvent($TestName, $properties, $metrics)

    [PSCustomObject]@{
        RunId = ${script:runConfig}.RunId
        TestName = $TestName
        PSVersion = $psVersionString
        AvgDurationMilliSeconds = $avgDuration
        AvgProcessorTimeMilliSeconds = $avgProcessorTime
    }
}
