# TODO
# device app metrics doesn't seem to work
# add interval param
# fix writing to CSV
# calc totals

$base_url = 'https://your-velocloud-instance.com/portal/rest'
$script:webSession = $null
$username = ''
$password = ''

Import-Module "$PSScriptRoot\velocloud_lookups.ps1"

# set the current location to the same location as the script and create the /Output directory
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Path 'Output'

function Main
{
    # authenticate
    Login-VeloCloud

    # get list of edges
    $edges = Get-Edges

    # just for testing, get the first 5
    $edges = $edges | select -First 5
    $edgeNum = 0
    $edgeCount = $edges.Count

    # loop through all the edges and get data for each one
    foreach ($edge in $edges)
    {
        $edgeNum++
        Write-Host "Edge $edgeNum/$edgeCount $($edge.name) (edge $($edge.id))"

        # strip non-alphanumeric characters from the edge name to make a valid windows filename
        # if you aren't familiar with regex syntax: https://www.regular-expressions.info/reference.html
        $edgeCleanName = [Regex]::Replace($edge.name, '[^a-zA-Z0-9]','')

        # query usage for each app in this edge
        $apps = Get-EdgeMetrics -EdgeId $edge.id `
                                -MetricName 'App'
        
        # calculate the total data usage for all apps
        $totalAppData = $apps | Measure-Object -Property totalBytes -Sum

        # build app usage data for writing to CSV
        $appDataToWrite = $apps | foreach-object { [PSCustomObject]@{
            'edge name'  = $edge.name
            'app name'   = Get-VeloCloudAppName -AppId $_.name
            'usage (MB)' = Format-UsageInMb -Usage $_.totalBytes
        }}

        $appDataToWrite | Export-Csv -Path "Output\App usage - $edgeCleanName.csv"

        # query usage for each link in this edge (to get bandwidth etc)
        $linkMetrics = Get-EdgeMetrics  -EdgeId $edge.id `
                                        -MetricName 'Link'

        # build link data for writing to CSV
        $linkDataToWrite = $linkMetrics | foreach-object { [PSCustomObject]@{
            'edge name'  = $edge.name
            'link name'  = $_.link.displayName
            'link type'  = $_.name
            'app name'   = Get-VeloCloudAppName -AppId $_.name
            'bandwidth Rx (MBbps)' = Format-UsageInMb -Usage $_.bpsOfBestPathRx
            'bandwidth Tx (MBbps)' = Format-UsageInMb -Usage $_.bpsOfBestPathTx
        }}

        $linkDataToWrite | Export-Csv -Path "Link bandwidth - $edgeCleanName.csv"

        # query usage for each device in this edge
        $edgeDeviceMetrics = Get-EdgeMetrics    -EdgeId $edge.id `
                                                -MetricName 'Device'

        # build device usage for writing to CSV
        $deviceDataToWrite = $edgeDeviceMetrics | foreach-object { [PSCustomObject]@{
            'edge name'  = $edge.name
            'device name'  = $_.info.hostName
            'app name'   = Get-VeloCloudAppName -AppId $_.application
            'category'   = Get-VeloCloudCategoryName -CategoryId $_.category
            'usage (Mb)' = Format-UsageInMb -Usage $_.totalBytes
        }}

        $deviceDataToWrite | Export-Csv -Path "Device usage - $edgeCleanName.csv"

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
            $deviceApps
        }
    }

    # write out summary data

}

function Login-VeloCloud
{
    # force TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $loginBody = @{
        'username' = $username
        'password' = $password
    }

    $loginRequest = CallApi -Path "/login/enterpriseLogin" `
                            -Body $loginBody `
                            -Method Post
    
    # TODO: check for failed logins
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
        #'interval' = @{
        #    'start' = 1554070363163
        #}
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

function CallApi ([string]$Path,
                  [HashTable]$Body,
                  [Microsoft.PowerShell.Commands.WebRequestMethod]$Method)
{
    $request = $null

    $bodyJson = $Body | ConvertTo-Json

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
        $request =  Invoke-RestMethod `
                        -Uri ($base_url + $Path) `
                        -Method Post `
                        -Body $bodyJson `
                        -WebSession $script:webSession #-Proxy "http://127.0.0.1:8888"
    }

    return $request
}

function Get-VeloCloudAppName ([int]$AppId)
{
    return $appsLookup[$AppId]
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

function CallApi2() {
    param(
        [string]$Path,
        [HashTable]$Body
    )

    # TODO: use params table and only have one call
    # $params = @{}
    $bodyJson = $Body | ConvertTo-Json
    # if using fiddler, add this line: -Proxy "http://127.0.0.1:8888"

    if($null -eq $script:webSession)
    {
        $response = Invoke-WebRequest -Uri ($base_url + $Path) -Method Post -Body $bodyJson -MaximumRedirection 0 -SessionVariable 'session' -UseBasicParsing #-Proxy "http://127.0.0.1:8888"
        $script:webSession = $session
    }
    else
    {
        $response = Invoke-WebRequest -Uri ($base_url + $Path) -Method Post -Body $bodyJson -MaximumRedirection 0 -WebSession $script:webSession -UseBasicParsing #-Proxy "http://127.0.0.1:8888"
    }

    #if($response.Headers['Set-Cookie'] -match 'velocloud.message')
    return $response
}

Main
