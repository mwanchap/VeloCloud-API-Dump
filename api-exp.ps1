# TODO
# device app metrics doesn't seem to work
# add interval param
# write to CSV
# calc totals
# progress reporting

$base_url = 'https://your-velocloud-instance.com/portal/rest'
$script:webSession = $null
$username = ''
$password = ''

Import-Module "$PSScriptRoot\velocloud_lookups.ps1"

function Main
{
    # authenticate
    Login-VeloCloud

    # get list of edges
    $edges = Get-Edges

    # just for testing, get the first 5
    $edges = $edges | select -First 5

    # loop through all the edges and get data for each one
    foreach ($edge in $edges)
    {
        # query usage for each app in this edge
        $apps = Get-EdgeMetrics -EdgeId $edge.id `
                                -MetricName 'App'

        # query usage for each link in this edge (to get bandwidth etc)
        $linkMetrics = Get-EdgeMetrics  -EdgeId $edge.id `
                                        -MetricName 'Link'

        # query usage for each device in this edge
        $edgeDeviceMetrics = Get-EdgeMetrics    -EdgeId $edge.id `
                                            -MetricName 'Device'


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


Main

# get a list of edges
$allMetrics = @()

# get metrics for edges
foreach ($edge in $edges)
{
    Write-Host "Processing: $($edge.Name)"
    $response = CallApi2 -Path '/metrics/getEdgeAppMetrics' -Body @{ 'edgeId' = $edge.id }
    $series = CallApi2 -Path '/metrics/getEdgeAppSeries' -Body @{ 'edgeId' = $edge.id }
    $appMetrics = $response.Content | ConvertFrom-Json

    foreach ($metric in $appMetrics)
    {
        $appName = $appsLookup[$metric.application]
        $bytes = $metric.totalBytes
        $allMetrics += New-Object -TypeName psobject -Property @{
            edge = $edge.Name;
            application= $metric.application;
            applicationName = $appName;
            totalBytes = $metric.totalBytes;
        }
    }
}

$allMetrics | Export-Csv -Path "C:\scratch\metricstest.csv"
