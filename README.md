# PSSnowball
Performance telemetry collection for trending data

Here is a sample for using the module for performance measurements:

```PowerShell
Import-Module "PSSnowball" -force
$results = @()

# Start run
# The PwshPath parameter is for testing a version of PowerShell other than the default installation.
Start-PSSnowballRun -Verbose -InstrumentationKey '<PerfAppInsightsKey>' -PwshPath '<PwshPath>'

# Make sure powershell analysis cache is setup
# Needed for testing PowerShell modules / cmdlets to account for Command Discovery and Auto loading.
Invoke-PSSnowballRunInitScript -ScriptBlock { Get-Module -ListAvailable } | Out-Null

# Get-Help test
$results += Invoke-PSSnowballTest -TestName "GetHelpNonExistent" -ScriptBlock { Get-Help DoesNotExist -ErrorAction SilentlyContinue} -Setup { $ProgressPreference = 'silentlycontinue'; $originalPath = $env:PSModulePath; $env:PSModulePath = (Join-Path $PSHOME "Modules")} -TearDown { $env:PSModulePath = $originalPath } -Verbose

# Get-Command test
$results += Invoke-PSSnowballTest -TestName "GetCommand" -ScriptBlock { Get-Command } -Setup { $originalPath = $env:PSModulePath; $env:PSModulePath = (Join-Path $PSHOME "Modules")} -TearDown { $env:PSModulePath = $originalPath } -Verbose

# Get-Module ListAvailable test
$results += Invoke-PSSnowballTest -TestName "GetModuleListAvailable" -ScriptBlock { Get-Module -ListAvailable } -Setup { $originalPath = $env:PSModulePath; $env:PSModulePath = (Join-Path $PSHOME "Modules")} -TearDown { $env:PSModulePath = $originalPath } -Verbose

# Stop run
Stop-PSSnowballRun

# Results
$results

RunId                        : 3cff31bf-0952-4536-956f-6a4ace23c91c
TestName                     : GetHelpNonExistent
PSVersion                    : 7.1.0
Platform                     : Windows
AvgDurationMilliSeconds      : 818.900964
AvgProcessorTimeMilliSeconds : 823.4375

RunId                        : 3cff31bf-0952-4536-956f-6a4ace23c91c
TestName                     : GetCommand
PSVersion                    : 7.1.0
Platform                     : Windows
AvgDurationMilliSeconds      : 6.608528
AvgProcessorTimeMilliSeconds : 6.5625

RunId                        : 3cff31bf-0952-4536-956f-6a4ace23c91c
TestName                     : GetModuleListAvailable
PSVersion                    : 7.1.0
Platform                     : Windows
AvgDurationMilliSeconds      : 18.23044
AvgProcessorTimeMilliSeconds : 23.4375
```
