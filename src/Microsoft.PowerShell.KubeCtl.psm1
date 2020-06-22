# a couple of module wide resources
$TextInfo = [CultureInfo]::new("en-us",$false).TextInfo
$Executable = "kubectl"

class Readiness {
    [int]$Count
    [int]$Ready
    [string]ToString() {
        return ("{0}/{1}" -f $this.ready, $this.count)
    }
    Readiness([string]$r) {
        $this.,$this.count = $r.Split("/")
    }
    Readiness([int]$c, [int]$r) {
        $this.count = $c
        $this.Ready = $r
    }
}

class Deployment
{

    hidden [pscustomobject]$OriginalObject
    [string]$Namespace
    [string]$Name
    [Readiness]$Readiness
    [int]$Updated
    [int]$Available
    [DateTime]$StartDate
    Deployment ( [pscustomobject]$o ) {
        $this.OriginalObject = $o
        $this.Namespace =  $o.metadata.namespace
        $this.Name = $o.metadata.name
        $this.Readiness = [Readiness]::new($o.status.replicas,$o.status.readyreplicas)
        $this.Updated = $o.status.updatedReplicas
        $this.Available = $o.status.availableReplicas
        $this.StartDate = $o.metadata.creationTimestamp
    }
}



function Get-ClassDefinition ( [psobject]$configuration, [ref]$className )
{
    $outputType = $configuration.TypeName
    $className.Value = $outputType
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('class ' + $outputType + " {")
    $null = $sb.AppendLine('# fields')
    $null = $configuration.Fields.Foreach({$sb.AppendLine('    [object]$' + $textinfo.ToTitleCase($_.PropertyName.ToLower().Replace(" ","").Replace("-","")))})
    $null = $sb.AppendLine('    hidden [psobject]$originalObject')
    $null = $sb.AppendLine('# originalObject member')
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine('# constructor')
    $null = $sb.AppendLine("    $outputType ([pscustomobject]`$o) {")
    $null = $sb.AppendLine('    if ( $env:DebugAutoConstructor -eq $true ) {')
    $null = $sb.AppendLine('        wait-debugger')
    $null = $sb.AppendLine('    }')
    $null = $configuration.Fields.Foreach({$sb.AppendLine('        $this.' +  $textinfo.ToTitleCase($_.PropertyName.ToLower().Replace(" ","").Replace("-","")) + ' = ' + $_.PropertyReference)})
    $null = $sb.AppendLine('        $this.originalObject = $o')
    $null = $sb.AppendLine('    }')
    $null = $sb.AppendLine('}')
    return $sb.ToString()
}

function Get-ResourceTypes ( [string]$resourceJson = "${psscriptroot}/ResourceConfiguration.json")
{
    $script:classStrings = @()
    $resources = Get-Content $resourceJson | ConvertFrom-Json
    foreach ($resourceType in $resources) {
        [ref]$className = ""
        $classdef = Get-ClassDefinition -configuration $resourceType -className $className
        # create the classes only if they're not already available
        if ( ! ("$className" -as [type]) ) {
            $script:classStrings += $classdef
        }
    }
    # this instantiates all the types that will be needed
    return ($script:classStrings -join "`n`n")
}

function Initialize-Formatters ( [string]$resourceJson = "${psscriptroot}/ResourceConfiguration.json")
{
    $resources = Get-Content $resourceJson | ConvertFrom-Json
    $generatedFormatFile = "${PSScriptRoot}/Generated.Format.ps1xml"
    .{
        '<Configuration>'
        '  <ViewDefinitions>'
        foreach ( $resource in $resources ) {
            '    <View>'
            '     <Name>{0}Table</Name>' -f $resource.TypeName
            '     <ViewSelectedBy>'
            '      <TypeName>{0}</TypeName>' -f $resource.TypeName
            '     </ViewSelectedBy>'
            '     <TableControl>'
            '      <TableHeaders>'
            $resource.Fields.Foreach({'         <TableColumnHeader><Label>{0}</Label></TableColumnHeader>' -f $textInfo.ToTitleCase($_.PropertyName.ToLower().Replace(" ","").Replace("-",""))})
            '      </TableHeaders>'
            '      <TableRowEntries>'
            '       <TableRowEntry>'
            '        <TableColumnItems>'
            $resource.Fields.Foreach({'         <TableColumnItem><PropertyName>{0}</PropertyName></TableColumnItem>' -f $textInfo.ToTitleCase($_.PropertyName.ToLower().Replace(" ","").Replace("-",""))})
            '        </TableColumnItems>'
            '       </TableRowEntry>'
            '      </TableRowEntries>'
            '     </TableControl>'
            '    </View>'
        }
        '  </ViewDefinitions>'
        '</Configuration>'
    } > $generatedFormatFile
    $generatedFormatFile
}

function Get-KubeDeployment
{
    param ( $name = "*" )
    $items = Invoke-KubeCtl -verb get -resource deployment
    $items.ForEach({[deployment]::new($_)}).Where({$_.name -like "$name"})
}

$proxyFunctions = @{
    "get:deployments" = {
        [CmdletBinding()]
        param ($name = "*")
        $items = Invoke-KubeCtl -verb get -resource deployment
        $items.ForEach({[deployment]::new($_)}).Where({$_.name -like "$name"})
        }
    "get:pods" = {
        [CmdletBinding()]
        param ( $name = "*" )
        $items = Invoke-KubeCtl -verb get -resource pod
        $items.foreach({[Pod]::new($_)}).Where({$_.Name -like $name})
        }
    "get:endpoints" = {
        [CmdletBinding()]
        param ($name = "*")
        $items = Invoke-KubeCtl -verb get -resource endpoints
        $items.ForEach({[endpoints]::new($_)}).Where({$_.name -like "$name"})
    }
    "get:events" = {
        [CmdletBinding()]
        param ($name = "*")
        $items = Invoke-KubeCtl -verb get -resource events
        $items.ForEach({[events]::new($_)}).Where({$_.name -like "$name"})
    }
}

# NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE     IP           NODE            NOMINATED NODE   READINESS GATES
# kube-system   helm-install-traefik-z4j9n                0/1     Completed   1          2d18h   10.42.0.3    jwtraspbian04   <none>           <none>

class Pod {
    [string]$NameSpace
    [string]$Name
    [Readiness]$Ready
    [string]$Status
    [int]$Restarts
    [DateTime]$StartDate
    [URI]$Ip
    [string]$NodeName
    [string]$NominatedNode
    [string]$ReadinessGates
    hidden [pscustomobject]$OriginalObject
    Pod ([pscustomobject]$o ) {
        $this.OriginalObject = $o
        $this.Namespace = $o.metadata.namespace
        $this.name = $o.metadata.name
        $this.StartDate = $o.metadata.creationTimestamp
        $this.NodeName = $o.spec.nodeName
        $this.Ip = $o.status.podip
        $this.Restarts = ($o.status.containerStatuses.restartcount|measure-object -sum ).sum
        [int]$totalCount = $o.Status.containerStatuses.Count
        [int]$readyCount = $o.status.ContainerStatuses.State.running.Count
        $this.Ready = [Readiness]::new($totalCount, $readyCount)
        $this.Status = $o.status.phase
    }

}

function Get-KubePod2
{
    param ( $name = ".*" )
    $items = (& ${executable} get pods --all-namespaces -o json | ConvertFrom-Json).Items
    $items.foreach({[Pod]::new($_)}).Where({$_.Name -match $name})
}

class KubeResource {
    [string]$Name
    [string[]]$Shortnames
    [string]$ApiGroup
    [bool]$Namespaced
    [string]$Kind
    [string[]]$Verbs
    KubeResource([int[]]$offsets, $string)
    {
        $this.name = $string.substring($offsets[0],($offsets[1]-1)).Trim()
        $this.Shortnames = $string.substring($offsets[1],($offsets[2]-$offsets[1])).Replace(" ","").Split(",")
        $this.ApiGroup = $string.substring($offsets[2],($offsets[3]-$offsets[2])).Trim()
        $this.Namespaced = [bool]::Parse($string.substring($offsets[3],($offsets[4]-$offsets[3])).Trim())
        $this.Kind = $string.substring($offsets[4],($offsets[5]-$offsets[4])).Trim()
        $this.Verbs = $string.substring($offsets[5]).Replace("[","").Replace("]","").Split(" ")
    }
    [string]ToString()
    {
        return $this.Name
    }
}


$KUBERESOURCES = $null
if ( $global:DEFAULTSESSION ) {
    $DEFAULTSESSION = $global:DEFAULTSESSION
}
else {
    $DEFAULTSESSION = $null
}

if ( $global:DefaultRequireSudo ) {
    $DefaultRequireSudo = $global:DefaultRequireSudo
}
else {
    $DefaultRequireSudo = $false
}

<#
.SYNOPSIS
Set the session for executing kubectl
.DESCRIPTION
Do not use, untested
#>
function Set-DefaultPSSession
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param ( [System.Management.Automation.Runspaces.PSSession]$Session )
    if ( $PSCmdlet.ShouldProcess("session")) {
        $script:DEFAULTSESSION = $Session
    }
}

<#
.SYNOPSIS
Get the session for executing kubectl
.DESCRIPTION
Do not use, untested
#>
function Get-DefaultPSSession
{
    [CmdletBinding()]
    param ()
    return $script:DEFAULTSESSION
}

<#
.SYNOPSIS
Get whether invoking kubectl requries sudo
.DESCRIPTION
Do not use, it is not cross platform yet
#>
function Get-KubeRequireSudo
{
    [CmdletBinding()]
    param ()
    return $script:DefaultRequireSudo
}

<#
.SYNOPSIS
Set whether invoking kubectl requries sudo
.DESCRIPTION
Do not use, it is not cross platform yet
#>
function Set-KubeRequireSudo
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param ( [bool]$RequireSudo )
    if ( $PSCmdlet.ShouldProcess("require sudo")) {
        $script:DefaultRequireSudo = $RequireSudo
    }
}

<#
.SYNOPSIS
Retrieve the available api-resources
.DESCRIPTION
This converts the table output of kubectl api-resources to
a set of objects which will then be used to create the proxy functions
#>
function Get-KubeResource
{
    [CmdletBinding()]
    param ( [string]$name = ".*", [switch]$Force )
    # kubectl api-resources -o wide
    # We do a little caching here, -force will ensure we go back and collect resources
    if ( ! $script:KUBERESOURCES -or $Force) {
        $res = Invoke-KubeCtl -verb "" -resource "api-resources"  -noJson -arguments @("-o","wide") -noAllNamespace
        $FIELDS = "NAME","SHORTNAMES","APIGROUP","NAMESPACED","KIND","VERBS"
        $offsets = $FIELDS.ForEach({$res[0].IndexOf("$_")})
        $script:KUBERESOURCES = $res[1..($res.count-1)].Foreach({[KubeResource]::new($offsets,$_)}).Where({$_.name -match $name})
    }
    return $script:KUBERESOURCES.Where({$_.name -match $name})
}

<#
.SYNOPSIS
Create the proxy functions for the module
.DESCRIPTION
This discovers the available resources and creates a proxy function that you can call
It essentially converts 'kubectl get pod' to 'Get-KubePod'
#>
function Initialize-ProxyFunction
{
    $r = Get-KubeResource
    export-modulemember -Function 'Invoke-KubeCtl', 'Get-KubeResource', 'Initialize-ProxyFunction', 'Get-DefaultPSSession', 'Set-DefaultPSSession', 'Get-KubeRequireSudo', 'Set-KubeRequireSudo'
    # for each resource that has a get verb, create a function
    # which can retrieve and display it.
    # in the case that there is a provided implementation, use it
    # otherwise create default which has a name parameter
    # This should probably include a namespace parameter where the resource supports namespaces
    $getters = $r.where({ $_.verbs -contains "get" })
    $getters.foreach({
        $resource = $_.Name
        $kind = $_.kind
        $proxyKey = "get:{0}" -f $resource
        $implementation = $proxyFunctions[$proxyKey]
        $functionName = "Get-Kube${kind}"
        if ( $implementation ) {
            [scriptblock]::Create("function global:${functionName} {
                    $implementation
                }").Invoke()
        }
        elseif ($resource -as [type]) {
            [scriptBlock]::Create("function global:$functionName {
                    [CmdletBinding()]
                    param ([string]`$Name = `"*`")
                    (Invoke-KubeCtl -Verb get -resource $resource).Foreach({[$resource]::new(`$_)}).Where({`$_.Name -like `"`$Name`"}) }").Invoke()
        }
        else {
            [scriptBlock]::Create("function global:$functionName {
                    [CmdletBinding()]
                    param ()
                    Invoke-KubeCtl -Verb get -resource $resource }").Invoke()
        }
        Export-ModuleMember -Function $functionName
    })

}

<#
.SYNOPSIS
Invoke kubectl with arguments
.DESCRIPTION
Invoke kubectl with arguments
#>
function Invoke-KubeCtl
{
    [CmdletBinding()]
    param (
        [switch]$requireSudo,
        [System.Management.Automation.Runspaces.PSSession]$session = $script:DEFAULTSESSION,
        [string]$verb,
        [string]$resource,
        [switch]$noJson,
        [switch]$noAllNamespace,
        [string[]]$arguments
        )

    [string[]]$action = @()
    if ( $requireSudo -or $script:DefaultRequireSudo) {
        $action += "sudo ${executable}"
    }
    else {
        $action += "${executable}"
    }

    $action += $verb
    $action += $resource
    if ( ! $noAllNamespace ) {
        $action += "--all-namespaces"
    }
    if ( ! $noJson ) {
        $action += "-o","json"
    }
    $action += $arguments
    # always multiplex the error stream to be sure that we get them
    # we will de-multiplex them after the execution.
    $action += '2>&1'
    # create the script block to execute
    [scriptblock]$action = [scriptblock]::create($action)

    Write-Debug -Message ("SESSION IS NULL: {0}" -f $null -eq $script:DEFAULTSESSION)
    Write-Debug -Message $action.ToString()
    if ( $session ) {
        $allOutput = invoke-command -session $session -scriptblock $action
    }
    else {
        $allOutput = & $action
    }
    $execErrors = $allOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord]}
    $result     = $allOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord]}

    # should this throw?
    if ( $execErrors ) {
        $execErrors | Write-Error 
    }


    if ( ! $noJson ) {
        $convertedResult = $result | ConvertFrom-Json
        $convertedResult.Items
    }
    else {
        return $result
    }
}

# retrieve the resource types as PowerShell classes
# and add them and make them available to the module
$classStr = Get-ResourceTypes
$sb = [scriptblock]::create($classStr)
. $sb
# add the formatters and add them to the module
$generatedFormatFile = Initialize-Formatters
update-formatdata $generatedFormatFile
# generate the proxy functions
Initialize-ProxyFunction
