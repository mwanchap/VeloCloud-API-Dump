$base_url = 'https://your-velocloud-domain/portal/rest'
$username = ''
$password = ''

function Main
{
    # authenticate
    Login-VeloCloud

    # get list of edges
    $edges = Get-Edges

    # just for testing, limit processing to the first 5
    # $edges = $edges | select -First 5

    # to select only a single edge, uncomment the below
    # $edges = $edges | where name -like "*edge name*" # leave the *asterisks*, they're required for -like to find a partial match

    $edgeNum = 0
    $edgeCount = $edges.Count

    # loop through all the edges and get data for each one
    foreach ($edge in $edges)
    {
        $edgeNum++
        Write-Progress -Activity "Edge $edgeNum/$edgeCount $($edge.name) (edge $($edge.id))" -PercentComplete (($edgeNum/$edgeCount)*100)
        

        # strip non-alphanumeric characters from the edge name to make a valid windows filename
        # if you aren't familiar with regex syntax: https://www.regular-expressions.info/reference.html
        $edgeCleanName = [Regex]::Replace($edge.name, '[^a-zA-Z0-9]','')

        # get QoS data for this edge
        $qosEvents = Get-EdgeQosEvents -EdgeId $edge.id

        # overall quality score 0 is the one used on the site
        $qualityScore = $qosEvents.overallLinkQuality.score.0
        
        $qosDataToWrite = [PSCustomObject]@{
            'edge name' = $edge.name
            'QoS score' = $qualityScore
        }

        $qosDataToWrite | Export-Csv -Path "Output\Edge QoS.csv" -NoTypeInformation -Append

        # query usage for each app in this edge
        $apps = Get-EdgeMetrics -EdgeId $edge.id `
                                -MetricName 'App'
        
        # calculate the total data usage for all apps
        $totalAppData = $apps | Measure-Object -Property totalBytes -Sum

        # build app usage data for writing to CSV
        $appDataToWrite = $apps | ForEach-Object { [PSCustomObject]@{
            'edge name'  = $edge.name
            'app name'   = Get-VeloCloudAppName -AppId $_.name
            'usage (MB)' = Format-UsageInMb -Usage $_.totalBytes
        }}

        $appDataToWrite | Export-Csv -Path "Output\App usage - $edgeCleanName.csv" -NoTypeInformation

        # query usage for each link in this edge (to get bandwidth etc)
        $linkMetrics = Get-EdgeMetrics  -EdgeId $edge.id `
                                        -MetricName 'Link'

        # build link data for writing to CSV
        $linkDataToWrite = $linkMetrics | ForEach-Object { [PSCustomObject]@{
            'edge name'  = $edge.name
            'link name'  = $_.link.displayName
            'link type'  = $_.name
            'bandwidth Rx (MBbps)' = Format-UsageInMb -Usage $_.bpsOfBestPathRx
            'bandwidth Tx (MBbps)' = Format-UsageInMb -Usage $_.bpsOfBestPathTx
        }}

        $linkDataToWrite | Export-Csv -Path "Output\Link bandwidth - $edgeCleanName.csv" -NoTypeInformation

        # query usage for each device in this edge
        $edgeDeviceMetrics = Get-EdgeMetrics    -EdgeId $edge.id `
                                                -MetricName 'Device'

        # build device usage for writing to CSV
        $deviceDataToWrite = $edgeDeviceMetrics | ForEach-Object { [PSCustomObject]@{
            'edge name'  = $edge.name
            'device name'  = $_.info.hostName
            'usage (Mb)' = Format-UsageInMb -Usage $_.totalBytes
        }}

        $deviceDataToWrite | Export-Csv -Path "Output\Device usage - $edgeCleanName.csv" -NoTypeInformation

        # declare empty device app data array, to hold info for all the devices in the edge
        $deviceAppDataToWrite = @()

        foreach ($device in $edgeDeviceMetrics)
        {
            $deviceQueryParams = @{
                'filters' = @(@{
                    'field' = 'device'
                    'op' = '='
                    'values' = @($device.name)
                })
            }

            $deviceApps = Get-EdgeMetrics   -EdgeId $edge.id `
                                            -MetricName 'App' `
                                            -ExtraParams $deviceQueryParams

            # add this device's app usage and info, for writing to CSV
            $deviceAppDataToWrite += $deviceApps | ForEach-Object { [PSCustomObject]@{
                'edge name'  = $edge.name
                'device name'= $device.info.hostName
                'app name'   = Get-VeloCloudAppName -AppId $_.application
                'category'   = Get-VeloCloudCategoryName -CategoryId $_.category
                'usage (Mb)' = Format-UsageInMb -Usage $_.totalBytes
            }}
        }

        $deviceAppDataToWrite | Export-Csv -Path "Output\Device app usage - $edgeCleanName.csv" -NoTypeInformation
    }

    Write-Host "Finished!"
}

function Login-VeloCloud
{
    # force TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $script:webSession = $null

    $loginBody = @{
        'username' = $username
        'password' = $password
    }

    $loginRequest = CallApi -Path "/login/enterpriseLogin" `
                            -Body $loginBody `
                            -Method Post
    
    # for some weird reason instead of returning an error for failed api logins, it returns a success
    # message containing a HTML login form containing an error (perhaps to support legacy clients?)
    # so instead, just check if it's not an empty string, which is what gets returned on success
    if ($loginRequest.Length -gt 0)
    {
        Write-Error "Incorrect username, password or velocloud instance URL"
        Write-Warning "More info: $loginRequest"
    }
}

function Get-Edges
{
    $response = CallApi -Path '/enterprise/getEnterpriseEdges' `
                        -Body @{} `
                        -Method Post

    return $response
}

function Get-EdgeMetrics ([int]$EdgeId, [string]$MetricName, [HashTable]$ExtraParams)
{
    $params = @{
        'id' = $EdgeId
        'interval' = @{
            'start' = $startDate
            'end' = $endDate
        }
    }

    if($null -ne $ExtraParams)
    {
        $params += $ExtraParams
    }

    $response = CallApi -Path "/metrics/getEdge$($MetricName)Metrics" `
                        -Body $params `
                        -Method Post

    return $response
}

function Get-EdgeQosEvents ([int]$EdgeId)
{
    $params = @{
        'edgeId' = $EdgeId
        'maxSamples' = 1 # removes all the unused timeseries data (can't set this to 0 though)
        'interval' = @{
            'start' = $startDate
            'end' = $endDate
        }
    }

    $response = CallApi -Path "/linkQualityEvent/getLinkQualityEvents" `
                        -Body $params `
                        -Method Post

    return $response
}

function CallApi ([string]$Path,
                  [HashTable]$Body,
                  [Microsoft.PowerShell.Commands.WebRequestMethod]$Method)
{
    $request = $null

    # specifying depth is necessary because the default is 2; won't convert anything nested >3 deep!
    $bodyJson = $Body | ConvertTo-Json -Depth 5

    # need to create a session if one doesn't already exist, for storing the auth cookie
    if($null -eq $script:webSession)
    {
        $request =  Invoke-RestMethod `
                        -Uri ($base_url + $Path) `
                        -Method $Method `
                        -Body $bodyJson `
                        -SessionVariable 'webSession' #-Proxy "http://127.0.0.1:8888"
        
        $script:webSession = $webSession
    }
    else
    {
        # VeloCloud API randomly fails all the time, so retry a few times if that happens
        foreach($i in 1..10)
        {
            try
            {
                $request =  Invoke-RestMethod `
                            -Uri ($base_url + $Path) `
                            -Method Post `
                            -Body $bodyJson `
                            -WebSession $script:webSession #-Proxy "http://127.0.0.1:8888"
                
                break;
            }
            catch [System.Net.WebException]
            {
                Write-Warning "Error while querying VeloCloud API, retrying ($i/10). Error was: $($_.Exception.Message)"
            }
        }
    }

    return $request
}

function Get-VeloCloudAppName ([int]$AppId)
{
    $AppName = "Unknown"

    try
    {
        $AppName = $appsLookup[$AppId]
    }
    catch
    {
        Write-Warning "Unknown application: $AppId"
    }

    return $AppName
}

function Get-VeloCloudCategoryName ([int]$CategoryId)
{
    return $categoryLookup[$CategoryId]
}

# returns usage formatted as bytes to be formatted in MB
function Format-UsageInMb ([double]$Usage)
{
    return [Math]::Round($Usage / 1Mb, 5)
}

# add the lookup values for applications and categories
Import-Module "$PSScriptRoot\velocloud_lookups.ps1"

# create the /Output directory in the same location as the script, for writing CSVs
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Path "Output" -Force

# calculate report date range
# reporting across the last full week, from midnight on Monday through to the next Monday
# each date is a unix timestamp in milliseconds and needs to be in UTC

# calculate Monday of last full week (e.g. if it's Tuesday now, Today.DayOfWeek is 2, so -6 -2 = -8 days ago)
$todayDayNumber = [int][DateTime]::Today.DayOfWeek
$lastMonday = [DateTime]::Today.AddDays(-6 -$todayDayNumber)

#convert to UTC and DateTimeOffset (necessary to access .ToUnixTimeMilliseconds)
$lastMondayUtc = [DateTimeOffset]$lastMonday.ToUniversalTime()

# convert to unix timestamp format via the handy-dandy method DateTimeOffset.ToUnixTimeMilliseconds
$startDate = $lastMondayUtc.ToUnixTimeMilliseconds()
$endDate = $lastMondayUtc.AddDays(7).ToUnixTimeMilliseconds()

# or to use a customised date range, comment out the above, uncomment the below, and change the dates
# $startDateString = "2019-01-31"
# $endDateString = "2019-02-28"
# $startDate = ([DateTimeOffset][DateTime]::Parse($startDateString).ToUniversalTime()).ToUnixTimeMilliseconds()
# $endDate = ([DateTimeOffset][DateTime]::Parse($endDateString).ToUniversalTime()).ToUnixTimeMilliseconds()

# actually run the script, starts in the "Main" function back up the top
Main