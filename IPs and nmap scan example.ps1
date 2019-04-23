# here's an example of how to use the VeloCloud API to get a list of link IPs and
# scan them with nmap to identify open ports that could be problematic

$base_url = 'https://your-velocloud-instance/portal/rest'
$script:webSession = $null
$username = ''
$password = ''

# set the current location to the same location as the script
Set-Location $PSScriptRoot

function Main
{
    # authenticate
    Login-VeloCloud

    # get list of edges
    $edges = Get-Edges

    # just for testing, uncomment to get only the first 5
    # $edges = $edges | select -First 5
    $edgeNum = 0
    $edgeCount = $edges.Count

    $linkDataToWrite = @()

    # loop through all the edges and get data for each one
    foreach ($edge in $edges)
    {
        $edgeNum++
        Write-Host "Edge $edgeNum/$edgeCount $($edge.name) (edge $($edge.id))"

        # query usage for each link in this edge (to get names and IPs etc)
        $linkMetrics = Get-EdgeMetrics  -EdgeId $edge.id `
                                        -MetricName 'Link'

        # build link data for writing to files
        # in this example, we're only interested in the gateway (GE1/2) links
        $linkDataToWrite += $linkMetrics | 
            Where-Object { $_.name -like "GE*" } |
            ForEach-Object { [PSCustomObject]@{
                'edge name'  = $edge.name
                'link name'  = $_.link.displayName
                'ip address'  = $_.link.ipAddress
                'link type'  = $_.name
        }}
    }

    $linkDataToWrite | Export-Csv -Path "Links and IPs.csv"
    $linkDataToWrite | select -ExpandProperty 'ip address' | Out-File "IPs.txt" -Encoding ascii
    
    # do the nmap scan using the list of IPs, but only show ports that are open all the way
    # obviously requires nmap for this to work.  Use chocolatey like a hero and install it with:
    # choco install nmap
    ."C:\Program Files (x86)\Nmap\nmap.exe" -iL "IPs.txt" -p 21,22,23,80,443 --open
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
