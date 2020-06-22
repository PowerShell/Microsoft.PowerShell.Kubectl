$CommandTopicTokens = @("Commands.*:$")
$UsageTopicToken = "Usage:"
$ExampleToken = "Examples:"
$OptionToken = "Options:"
$SubCommandTokens   = @("Available Commands", "Basic Commands \(Beginner\):", "Basic Commands \(Intermediate\):",
    "Deploy Commands:", "Cluster Management Commands:", "Troubleshooting and Debugging Commands:",
    "Advanced Commands:", "Settings Commands:", "Other Commands:" )
$SubCommandTokenPattern = $script:SubCommandTokens -join "|"
$IAM = "${PSScriptRoot}\KHP2.psm1"

[string[]]$allTokens = @($CommandTopicTokens, $UsageTopicToken, $ExampleToken, $OptionToken)
[System.Globalization.TextInfo]$TextInfo = [CultureInfo]::new("en-us",$false).TextInfo


class UsageInfo {
    [string]$Usage
    [bool]$supportsFlags
    [bool]$hasOptions
    hidden [string[]]$originalText
    UsageInfo([string[]]$text) {
        for ( $i = 0; $i -lt $text.Count; $i++ ) {
            if ( $text[$i] -match $script:UsageTopicToken ) {
                $i++
                while ( $text[$i] -ne "" ) {
                    $this.originalText += $text[$i]
                    $i++
                }
                break
            }
        }
        $this.Usage = ($this.originalText -join [environment]::newline).Trim()
        if ( $this.Usage -match "\[flags\]") { $this.supportsFlags = $true }
        if ( $this.Usage -match "\[options\]") { $this.hasOptions = $true }
    }
    [string]ToString() {
        return $this.Usage
    }
}

class ExampleInfo {
    [string]$Description
    [string]$Command
    ExampleInfo([string[]]$text) {
        foreach ( $line in $text ) {
            if ( "${line}".Trim() -match "^#" ) {
                $this.Description += "${line}".Trim(" #")
            }
            else {
                $this.Command += "${line}".Trim()
            }
        }
    }
    static [ExampleInfo[]]GetExamples([string[]]$text) {
        [ExampleInfo[]]$examples = @()
        $getExamples = $false
        for ( $i = 0; $i -lt $text.Length; $i++) {
            if ( $text[$i] -match "^Examples:" ) {
                $getExamples = $true
                continue
            }
            if ( $getExamples ) {
                if ( $text[$i][0] -match "^[A-Z]" ) {
                    break
                }
                if ( $text[$i].Length -eq 0 ) {
                    continue
                }
                if ( $text[$i].Trim() -match "^#" ) {
                    $examples += [ExampleInfo]::new($text[$i..++$i])
                }
            }
        }
        return $examples
    }
    [string]ToString() {
        return $this.Command
    }
}


# note that for PowerShell, we won't have parameter aliases
# An option takes the shape of '--<name>=<defaultvalue>: <description>"
# it can also look like '-<n>, --<name>=<defaultvalue>: <description>" where '-<n>' is an option alias
# we through away the aliases
# The <defaultvalue> might be something that we can interpret, so try
# also, some options can be converted to powershell switches (their default value is True or False).
# if the default value is 'True',
# convert that to "No<name>" when building the string which represents the option
class ParameterInfo {
    # we need to track the original name of the parameter
    [string]$OriginalParameterName
    [string]$Name
    [string]$Description
    [object]$DefaultValue
    [type]$ValueType
    [bool]$IsMandatory
    hidden [bool]$Parsed
    hidden [string]$originalText
    ParameterInfo ([string]$text, [bool]$isMandatory = $false) {
        $this.originalText = $text
        if ( $text -match ".* --(?<option>.[^ ]*): (?<Description>.*)" ) {
            $pname,$default = $matches['option'] -split "="
            $this.OriginalParameterName = "--${pname}"
            $pDefaultValue = $default.Trim("'")
            # $this.Name = "${pname}" # .Trim() -replace "-(.)",{($_ -replace "-").ToUpper()} -replace "^(.)",{"$_".ToUpper()}
            # strip away all the "-" and capitalize the first letter of every "word"
            $this.Name = ("${pname}" -split "-").foreach({${script:TextInfo}.ToTitleCase($_)}) -join ""
            if ( $this.Name -eq "DryRun" ) { $this.Name = "WhatIf" }
            $this.Description = $matches['Description'].Trim()
            $this.IsMandatory = $isMandatory
            $this.Parsed = $true
            $v = $null
            if ( [string]::isnullOrEmpty($pDefaultValue)) {
                $this.ValueType = [string]
            }
            elseif ( [int]::TryParse($pDefaultValue, [ref]$v)) {
                $this.ValueType = [int]
                $pDefaultValue = $v
            }
            elseif ( [double]::TryParse($pDefaultValue, [ref]$v)) {
                $this.ValueType = [double]
                $pDefaultValue = $v
            }
            elseif ( $pDefaultValue -eq '[]' ) {
                $this.ValueType = [array]
                $pDefaultValue = @()
            }
            elseif ( $pDefaultValue -eq 'true' -or $pDefaultValue -eq 'false' ) {
                $this.ValueType = [bool]
                $pDefaultValue = [bool]::Parse($pDefaultValue)
            }
            else {
                $this.ValueType = [string]
            }
            $this.DefaultValue = $pDefaultValue
        }
        else {
            Write-Warning "Could not convert '$text' into a parameter"
        }
    }

    static [ParameterInfo[]]GetParameters([string[]]$text) {
        [ParameterInfo[]]$p = @()
        for($i = 0; $i -lt $text.Count; $i++) {
            if ( $text[$i] -match "^Options:" ) {
                $i++
                do {
                    if ( $i -ge $text.Count ) { break }
                    $p += [parameterinfo]::new($text[$i], $false)
                } while ( $text[++$i] -ne "" )
            }
        }
        return $p
    } 

    # this takes the usage text and retrieves the parameters which are not options or flags
    # they are mandatory
    static [ParameterInfo[]]GetMandatoryParameters([string]$text) {
        [parameterinfo[]]$mp = @()
        return $mp
    }

    [string]ToString() {
        # this is a bool, we convert it to a switch parameter
        if ( $this.ValueType -eq [bool] ) {
            $pName = $this.Name
            if ( $this.DefaultValue ) {
                $pName = "No${pName}"
            }
            $pString = '[Parameter(Mandatory=${0})][switch]${{{1}}}' -f $this.IsMandatory,$pName
        }
        elseif ( $this.ValueType -eq [array] -and ! $this.DefaultValue ) {
                $pString = '[Parameter(Mandatory=${0})][{1}]${{{2}}} = @()' -f $this.IsMandatory,$this.ValueType,$this.Name
        }
        elseif ( $this.ValueType -eq [string] -and $this.DefaultValue ) {
                $pString = '[Parameter(Mandatory=${0})][{1}]${{{2}}} = "{3}"' -f $this.IsMandatory,$this.ValueType,$this.Name,$this.DefaultValue
            
        }
        elseif ( $this.DefaultValue ) {
                $pString = '[Parameter(Mandatory=${0})][{1}]${{{2}}} = {3}' -f $this.IsMandatory,$this.ValueType,$this.Name,$this.DefaultValue
        }
        else {
            $pString = '[Parameter(Mandatory=${0})][{1}]${{{2}}}' -f $this.IsMandatory,$this.ValueType,$this.Name
        }
        return $pString
    }
}

# general options for kubectl are a little different. The tag does not exist, so we will force it
class KubeGeneralOptions {
    static [ParameterInfo[]]$Parameters
    static KubeGeneralOptions() {
        $text = Invoke-Kubectl options | Where-Object { "$_" }
        $text[0] = "Options:"
        [KubeGeneralOptions]::Parameters = [ParameterInfo]::GetParameters($text)
    }
}

class Command {
    [string]$Command
    [string[]]$CommandElements
    [string]$Description
    [UsageInfo]$Usage
    [Command[]]$SubCommands
    [ParameterInfo[]]$Parameters
    [ParameterInfo[]]$MandatoryParameters
    [ExampleInfo[]]$Examples
    hidden [string[]]$originalText

    # don't check the MandatoryParameters, or the CommonParameters
    [bool]SupportsWhatIf() {
        return [bool]$this.Parameters.Where({$_.Name -eq "WhatIf"})
    }

    Command ([string[]]$command, [string[]]$text ) {
        $this.Command = ($command -join " ").Trim()
        $this.CommandElements = $command # "$command".Trim()
        $this.originalText = $text
        #$c,$d = "$text".Trim().Split("  ", 2, [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {"$_".Trim()}
        #$this.Command = $c
        $this.Description = [Command]::GetDescription($text).Trim()
        $this.Parameters = [ParameterInfo]::GetParameters($text)
        $this.Examples = [ExampleInfo]::GetExamples($text)
        $this.Usage = [UsageInfo]::new($text)
        $this.MandatoryParameters = [ParameterInfo]::GetMandatoryParameters($this.Usage.Usage)
        $this.SubCommands = $this.GetSubCommands($command, $text)
    }

    [Command[]]GetSubCommands([string[]]$commandElements, [string[]]$text) {
        [Command[]]$subCmds = @()
        #$jobs = @()
        #$jobResult = @()
        #$pattern = $script:SubCommandTokenPattern
        for ($i = 0; $i -lt $text.count; $i++ ) {
            if ( $text[$i] -match $script:SubCommandTokenPattern ) {
                $i++
                while ( $i -lt $text.count -and $text[$i][0] -eq " " ) {
                    $subcmd,$desc = $text[$i].Trim().split(" ",2, [System.StringSplitOptions]::RemoveEmptyEntries)
                    # we need to add help specifically here, since we're invoking kubectl directly
                    $elements = $commandElements + @($subcmd)
                    $subText = Invoke-Kubectl ($elements + "--help")
#                    $sc = [Command]::new($subcmd, $subText)
                    $sc = [Command]::new($elements, $subText)
                    $sc.CommandElements = $elements
                    $subCmds += $sc
        ######
        # ATTEMPT AT JOBS
        ######
        #            $cmdText = $text[$i]
        #            $jobs += Start-ThreadJob {
        #                $t = ${using:cmdText}
        #                $subcmd,$desc = $t.Trim().split(" ", 2, [System.StringSplitOptions]::RemoveEmptyEntries)
        #                $elements = $using:commandElements + @($subcmd) + "--help"
        #                $subText = kubectl $elements
        #                @{ Command = $subcmd; Description = $desc; Elements = $elements; Text = $subText }
        #                #$sc = [Command]::new($subcmd, $subText)
        #                #$sc.CommandElements = $elements
        #                #$sc
        #            }
                    $i++
                }
            }
        }
        #if ( $jobs.Count -gt 0 ) {
        #    Write-Host ($jobs.Count)
        #    wait-job $local:jobs
        #    $local:jobResult = Receive-Job $local:jobs
        #    foreach ( $c in $local:jobResult ) {
        #        if ( ! $c.Command ) {
        #            "whoops"
        #        }
        #        if ( ! $c.Elements ) {
        #            "whoops"
        #        }
        #        $sc = [Command]::new($c.Command, $c.Text)
        #        $sc.Elements = $c.Elements
        #        $subCmds += $sc
        #    }
        #}
        return $subCmds
    }

    [Command[]]GetAllCommands() {
        [Command[]]$cmds = @()
        $cmds += $this
        $cmds += $this.SubCommands.Foreach({$_.GetAllCommands()})
        return $cmds
    }

    [Command[]]GetBranchCommands() {
        [Command[]]$cmds = @()
        if ( $this.SubCommands.Count -gt 0 ) {
            $this.SubCommands.Foreach({$_.GetBranchCommands()})
            $cmds += $this.SubCommands
        }
        return $cmds

    }
    [Command[]]GetLeafCommands() {
        [Command[]]$cmds = @()
        if ( $this.SubCommands.Count -gt 0 ) {
            $cmds += $this.SubCommands.Foreach({$_.GetLeafCommands()})
        }
        else {
            $cmds += $this
        }
        return $cmds
    }

    # not all commands support -o json. We need a way to add it or not when we execute
    # the only way we can know is by going through the options
    [bool]SupportsJsonOutput() {
        return ($null -ne $this.Parameters.Where({$_.OriginalParameterName -eq "--output" -and $_.Description -match "json"}))
    }

    [string]CreateParamStatement() {
        $sb = [System.Text.StringBuilder]::new()
        $param = @()
        $sb.AppendLine("param (")
        $this.MandatoryParameters.Foreach({$param += $_.ToString()})
        $this.Parameters.Foreach({$param += $_.ToString()})
        $sb.AppendLine(($param -join ",`n")) # comma separate the parameters
        $sb.AppendLine(")")
        return $sb.ToString()
    }

    [string]CreateCommentBasedHelp() {
        $sb = [System.Text.StringBuilder]::new()
        $sb.AppendLine("<#")
        $sb.AppendLine(".SYNOPSIS")
        $sb.AppendLine($this.Description.Split("`n")[0])
        $sb.AppendLine()
        $sb.AppendLine(".DESCRIPTION")
        $sb.AppendLine($this.Description)
        $sb.AppendLine("The native usage for this command is:")
        $sb.AppendLine("  " + $this.Usage.Usage)
        $sb.AppendLine()
        foreach ( $p in $this.MandatoryParameters ) {
            $sb.AppendLine(".PARAMETER")
            $sb.AppendLine($p.Name)
            $sb.AppendLine($p.Description)
            $sb.AppendLine("The original kubenetes parameter is {0}" -f $p.OriginalParameterName)
            $sb.AppendLine()
        }
        foreach ( $p in $this.Parameters ) {
            $sb.Append(".PARAMETER ")
            $sb.AppendLine($p.Name)
            $sb.AppendLine($p.Description)
            $sb.AppendLine()
        }
        foreach ( $e in $this.Examples ) {
            $sb.AppendLine(".EXAMPLE")
            $sb.AppendLine('$ ' + $e.Command)
            $sb.AppendLine($e.Description)
            $sb.AppendLine()
        }
        $sb.AppendLine("#>")
        return $sb.ToString()
    }

    static [string]GetDescription([string[]]$text) {
        [string[]]$dText = ""
        for($i = 0; $i -lt $text.Count; $i++ ) {
            if ( $script:allTokens | Where-Object { $text[$i] -match $_ } ) {
                break
            }
            $dText += $text[$i]
        }
        return ($dText -join [Environment]::newline)
    }

    [string]CreateProxyFunction() {
        [string[]]$s = .{
            'function Invoke-Kube{0}' -f ($this.CommandElements -join "")
            '{'
            '[CmdletBinding()]'
            $this.CreateParamStatement()
            $this.GetParameterMap()
            '$commandArguments = $PSBoundParameters.Keys.Foreach({"{0} ''{1}''" -f $_parameterMap[$_],$PSBoundParameters[$_]})'
            'if ( $env:DEBUGPROXYFUNCTION -eq 1 ) { wait-debugger }'
            if ( $this.SupportsJsonOutput ) {
                'kubectl $commandArguments -o json'
            }
            else {
                'kubectl $commandArguments'
            }
            '}'
        }
        wait-debugger
        return ($s -join [environment]::NewLine)
    }

    # this captures the information about the parameters in a .psd block.
    # this is needed when we want to take the parameters that the user provided and turn them back into the
    # strings we need when we call the actual command
    [string]GetParameterMap() {
        [string[]]$parameterStrings = '$_parameterMap = @{ '
        foreach ( $parameter in $this.Parameters ) {
            $parameterStrings += "'{0}' = '{1}'" -f $parameter.Name,$parameter.OriginalParameterName
        }
        $parameterStrings += "}"
        return ($parameterStrings -join [Environment]::NewLine)
    }

    [string]ToString() {
        return "kubectl " + ($this.CommandElements -join " ")
    }
}
# invoke kubectl and log it
function Invoke-Kubectl {
    [CmdletBinding()]
    param ( [Parameter(ValueFromRemainingArguments,Position=0)][string[]]$command )
    $p = "kubectl $($command -join ' ')"
    # show-prog -message "$p"
    write-verbose -verb "$p"
    $text = kubectl $command
    if ( ! $text ) {
        Wait-Debugger
    }
    $text
}

function Get-CommandInfo ( [string[]]$commandElements ) {
    $ce = $commandElements
    $ce += "--help"
    $text = Invoke-Kubectl -command $ce
    if ( $commandElements.Count -gt 0 ) {
        $cmd = $commandElements[0]
    }
    else {
        $cmd = ""
    }
    [Command]::new($cmd, $text)
}
function Get-KubeCtlGeneralOptions
{
    [KubeGeneralOptions]::Parameters
}

function Get-KubeCommands ()
{
    $cmd = Get-CommandInfo
    $cmd
}