$base_url = 'https://your-velocloud-domain/portal/rest'
$username = ''
$password = ''

function Main
{
    # authenticate
    Login-VeloCloud

    # get list of edges and their links
    $edges = Get-EdgeLinks

    # find the edges that have a stable usb link
    $problems = $edges | Where-Object {
        $_.recentLinks | Where-Object {
            $_.interface -like 'USB*' `
            -and $_.effectiveState -eq 'STABLE'
        }
    }
    
    Write-Host 'Edges with problems:'
    $problems.name

    $edgeNum = 0
    $edgeCount = $edges.Count
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

function Get-EdgeLinks
{
    $params = @{
        'with'= @('recentLinks')
        #can also include the following: site, ha, configuration, cloudServices, vnfs
    }

    $response = CallApi -Path '/enterprise/getEnterpriseEdgeList' `
                        -Body $params `
                        -Method Post

    return $response
}

function CallApi ([string]$Path,
                  [HashTable]$Body,
                  [Microsoft.PowerShell.Commands.WebRequestMethod]$Method)
{
    $script:apiStart = [DateTime]::Now
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
                        -SessionVariable 'webSession' `
                        -TimeoutSec 30 #-Proxy "http://127.0.0.1:8888"
        
        $script:webSession = $webSession
    }
    else
    {
        $request =  Invoke-RestMethod `
                        -Uri ($base_url + $Path) `
                        -Method Post `
                        -Body $bodyJson `
                        -WebSession $script:webSession `
                        -TimeoutSec 30 #-Proxy "http://127.0.0.1:8888"
    }

    $script:apiStop = [datetime]::Now
    $script:totalApiTime += ([timespan]($script:apiStop - $script:apiStart)).TotalMilliseconds
    return $request
}

# actually run the script, starts in the "Main" function back up the top
Main