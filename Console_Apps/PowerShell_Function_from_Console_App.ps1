#Function to convert legacy console application switches/parameters into a Key/Value pair
function Convert-ConsoleApplicationHelp {
    <#
    .SYNOPSIS
    Converts the help documentation from a legacy console application to PowerShell
    
    .DESCRIPTION
    Converts the help documentation from a legacy console application to PowerShell, it does this by parsing through the section headers if any exist.
    If none exist then it makes one one up, and continues processing the original help output.
    It then takes each switch and takes all the help information associated with each switch and transforms it into an object for later usage.
    
    .PARAMETER BinaryPath
    The filesystem path to where the binary is located, path only and not executable
    
    .PARAMETER BinaryExecutable
    The executable name in the BinaryPath with .exe or etc.
    
    .PARAMETER HelpArgument
    Us an additional help arguement other than the standard /?
    
    .EXAMPLE
    Convert-ConsoleApplicationHelp -BinaryExecutable xcopy.exe
    
    .EXAMPLE
    Convert-ConsoleApplicationHelp -BinaryExecutable xcopy.exe -HelpArgument /?

    .EXAMPLE
    Convert-ConsoleApplicationHelp -BinaryPath "C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy" -BinaryExecutable AzCopy.exe -HelpArgument /?
    
    .NOTES
    General notes
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Mandatory = $false,
            Position = 0,
            HelpMessage = 'The path to the binary, the full path is highly suggested'
        )]
        [string]$BinaryPath = 'C:\Windows\System32',

        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = 'The binary name, i.e. binary.exe'
        )]
        [string]$BinaryExecutable,
        
        [Parameter(
            Mandatory = $false,
            Position = 2,
            HelpMessage = 'The switch used to access the built in help, typically /?'
        )]
        [string]$HelpArgument = '/?' 
    )

    #Global Variables
    $SectionPatterns = "^::.*|^##.*" #This pattern matches on section header starts
    $SectionPatternCharactersToReplace = "[:|#]" #This pattern matches on characters to replace when sanatizing the section header
    [System.Collections.ArrayList]$SectionHeaderVariables = @() #ArrayList to store Variables of Parameter Sections
    [System.Collections.ArrayList]$ParametersInformation = @() #ArrayList to store Parameter Names and help information
    $LinePatterns = "^/.*" #Regex to designate the start of a parameter
    $BannedParameters = "^/@.*"#Parameters that are not PS Compliant


    #Functions
    #Function to add Paramter Help Information
    function Add-ParameterHelpInformation ($Lines, $i, $ParameterHelpInfo) {
        Write-Verbose "Line $i is a continuation of the help file for Parameter $ParameterName in Section $($Section.SectionVariable)"
        #The split is to remove excessive spaces, and then we rejoin it into a real string
        $ParameterHelpString = $Lines[$i].Trim() -split ' {2,}' -join ' ' #Remove Excess Spaces
        $ParameterHelpString = $ParameterHelpString.Replace('[','<').Replace(']','>') #Replace brackets with <,>, this is for PS Parameter compliance
        $ParameterHelpString = $ParameterHelpString.Replace('(','').Replace(')','') #Replace parentheses with nothing, this is for PS Parameter compliance
        $ParameterHelpInfo.Add($ParameterHelpString) | Out-Null
    
    }

    Write-Verbose 'CD''ing to the directory, because lord forbid we test paths in Program Files (x86)'
    #This is why, dear Microsoft you suck for this - https://stackoverflow.com/questions/4429112/powershell-combining-path-using-a-variable
    $CurrentDirectory = $pwd.Path
    Set-Location $BinaryPath

    Write-Verbose 'Testing the full path to the binary'
    if (!(Test-Path $BinaryExecutable)) {
        Write-Error -Message "Failed to find $BinaryPath, terminating now"
        exit
    }

    #Binary we want to convert, you know I'm really developing a hatred for legacy console applications
    $BinaryHelpInfo = Invoke-Expression "./$($BinaryExecutable) $($HelpArgument)"

    #Go back to the original directory as a precaution
    Write-Verbose 'Going back to the existing directory we started in'
    Set-Location $CurrentDirectory

    #Basic sanitization of the help data, removes excess lines and leading/trailing spaces
    $BinaryHelpInfo = $BinaryHelpInfo | Where-Object {$_}

    #Lets first scan for any possible section header match, if there are none were going to define a single section
    $NoSectionHeadersFound = (!($BinaryHelpInfo -match $SectionPatterns))

    #Loop through the file and find the major sections of data
    for ($i = 0; $i -lt $BinaryHelpInfo.Count; $i++) {
        #Regular section header scan
        if (($NoSectionHeadersFound) -and (!($NoSectionHeadersFoundOneTimeScan))) {
            Write-Verbose 'No Section Header was found so were going to say we found one'
            $BinaryHelpInfoHeaderMatch = $true
            $NoSectionHeadersFoundOneTimeScan = $true
        } else {
            $BinaryHelpInfoHeaderMatch = $BinaryHelpInfo[$i] -match $SectionPatterns
        }

        if ($BinaryHelpInfoHeaderMatch) {
            if (!($NoSectionHeadersFound)) {
                Write-Verbose "We matched a section header on line ""$($BinaryHelpInfo[$i])""" #Quotes for character escaping
            }

            #Set a temp variable as a indicator that we hit a section header
            $SectionHeaderLine = $true

            if ($NoSectionHeadersFound) {
                $HeaderNameReplaced = 'Options'
            } else {
                $HeaderNameReplaced = ($BinaryHelpInfo[$i] -replace $SectionPatternCharactersToReplace, '').Trim()
            }

            #We have to check for replacement so we get the real header
            if ($HeaderNameReplaced) {
                Write-Verbose "Section Header Name is $HeaderNameReplaced"
                $Script:SectionHeaderName = $HeaderNameReplaced
            }

            #Attempt to strip out the header name so we can use it later, or make one up        
            Write-Verbose "Section Header Name is ""$Script:SectionHeaderName"""
        } elseif (
                ($SectionHeaderLine) -and
                (!($BinaryHelpInfoHeaderMatch))
            ) {
            if ($SectionHeaderLine) {
                Write-Verbose "Line $i is the first line after the Section Header, were going to make a new storage var and flip a switch"
                $SectionVariableCountInt = 1
                do {
                    $SectionVariableName = "Section$($SectionVariableCountInt)"
                    if (!(Get-Variable $SectionVariableName -ErrorAction SilentlyContinue)) {
                        Write-Verbose "$SectionVariableCountInt is free, using that value for SectionVariableName"
                        New-Variable $SectionVariableName
                        $SectionVariableCreated = $true
                        Try {
                            $SectionHeaderNameObject = New-Object -TypeName psobject
                            $SectionHeaderNameObject | Add-Member -MemberType NoteProperty -Name 'SectionVariable' -Value $SectionVariableName
                            $SectionHeaderNameObject | Add-Member -MemberType NoteProperty -Name 'HeaderName' -Value $Script:SectionHeaderName

                            $SectionHeaderVariables.Add($SectionHeaderNameObject) | Out-Null
                        } Catch {}
                        $i-- #Step the loop back int 1 so we don't miss the line
                    } else {
                        $SectionVariableCreated = $false
                        Write-Verbose "$SectionVariableName was taken, incrementing +1 and looping"
                        $SectionVariableCountInt++
                    }
                } until ($SectionVariableCreated)

                #Let PowerShell know to start storing data to the new variable
                $SectionHeaderLine = $false
            }
            Write-Verbose "Line $i is after the section header ending, we will start processing it"
        } elseif (
                (!($SectionHeaderLine)) -and
                (!($BinaryHelpInfoHeaderMatch)) -and
                ($SectionHeaderVariables) #So we don't run this block on the first few lines
            ) {

            #Populate the Section variable with content
            Set-Variable -Name $SectionVariableName -Value @(
                (Get-Variable -Name $SectionVariableName).Value #Add the existing value so we don't lose it
                $BinaryHelpInfo[$i] #Add new line info
            )
        } #end Normal Line elseif
    } #End for loop

    #Find all sections that have actual options available and process them
    foreach ($Section in ($SectionHeaderVariables | Where-Object {($PSItem.HeaderName -like "*Options*")})) {
        $Lines = (Get-Variable -Name $Section.SectionVariable).Value | Where-Object {$PSItem} #Get the value and remove blank lines

        for ($i = 0; $i -lt $Lines.Count; $i++) {
            #Check if we are going to start definining a new parameter and store it as a boolean
            $NewParameter = if ($Lines[$i].Trim() -match $LinePatterns) {
                $true
            } else {
                $false
            }

            if (
                ($NewParameter) -and
                ($Lines[$i] -notmatch $BannedParameters)
            ) {
                #Split the line so we can get its help information, we do two split because console apps split different
                $LineSplit = ($Lines[$i].Split(':') -replace '/','').Trim() -split ' {2,}'
                Write-Verbose "Starting to work on a new parameter $($LineSplit[0]) on line $i" #While this should go above, we're leaving it here for debugging

                #If a new parameter commit the previous information
                if (
                    $ParameterName -and
                    $ParameterHelpInfo -and
                    $NewParameter -and
                    $LineSplit[0].Split().Count -eq 1
                ) {
                    Write-Verbose "We found an existing parameter $ParameterName so we will add it to the ArrayList"
                    
                    $ParameterToAdd = New-Object -TypeName psobject
                    $ParameterToAdd | Add-Member -MemberType NoteProperty -Name 'ParameterName' -Value $ParameterName
                    $ParameterToAdd | Add-Member -MemberType NoteProperty -Name 'ParameterHelp' -Value $ParameterHelpInfo

                    $ParametersInformation.Add($ParameterToAdd) | Out-Null
                    
                    Write-Verbose 'Remove the previous parameter information'
                    Remove-Variable ParameterName,ParameterHelpInfo,ParameterHelpString
                }

                if ($LineSplit.Count -gt 1) { 
                    if ($LineSplit[0].Split().Count -eq 1) {
                        Write-Verbose 'The line count is multiline'
                        $ParameterName = $LineSplit[0].Replace('[','').Replace(']','') #Replace illegal characters from parameters like this /MT[:n]
                        $ParameterHelpString = (($Lines[$i].Split(':') -split ' {2,}' -replace '/','').Where{$PSItem}[-1].Trim() -replace '<*.*>','').Trim() #Yes the second split must be that way, don't use the method

                        #Establish a variable to hold the help information in
                        [System.Collections.ArrayList]$ParameterHelpInfo = @()

                        #Add the help information to the HelpInfo Property
                        $ParameterHelpInfo.Add($ParameterHelpString) | Out-Null
                    } else {
                        Write-Verbose "Line $i is a continuation of the help file for Parameter $ParameterName in Section $($Section.SectionVariable)"
                        if ($Lines[$i] -like "*") {
                            Add-ParameterHelpInformation -Lines $Lines -i $i -ParameterHelpInfo $ParameterHelpInfo
                        }
                    }
                }
            } elseif ($ParameterName) { #Make sure there is an actual parameter were adding to
                Write-Verbose "Line $i is a continuation of the help file for Parameter $ParameterName in Section $($Section.SectionVariable)"
                if ($Lines[$i] -like "*") {
                    Add-ParameterHelpInformation -Lines $Lines -i $i -ParameterHelpInfo $ParameterHelpInfo
                }
            } #elseif ParameterName
        } #End for
    } #End foreach

    #Reformat and join together ParametersInformation, and remove possible duplicates
    $ParametersInformation = $ParametersInformation |
        Select-Object ParameterName,@{Name='ParameterHelp';Expression={($Psitem.ParameterHelp -join ' ').Trim('.')}} |
        Group-Object ParameterName |
        ForEach-Object {
            $PSItem.Group | Select-Object -First 1
        }

    #Return the new parameters
    return $ParametersInformation
}

#Function to interact with Convert-ConsoleApplicationHelp
function Invoke-ConsoleApplicationWrapper {
    <#
    .SYNOPSIS
    Main function to Convert-ConsoleApplicationHelp which converts legacy console arguments to PS Parameters
    
    .DESCRIPTION
    Uses Convert-ConsoleApplicationHelp to convert the legacy console applications arguments and help documentation to PS Parameters by using dynamic parameters
    
    .PARAMETER BinaryPath
    The full file system path to the binary folder
    
    .PARAMETER BinaryExecutable
    The binary name
    
    .PARAMETER HelpArgument
    What you would use on the legacy console application binary to show the help file, typically /?

    .PARAMETER ParameterSpacing
    Special parameter spacing for non standard parameter style of /Param Arg, AZCopy uses /Param:Arg

    .PARAMETER SeperateWindow
    Switch to spawn the process in a new window with Start-Process without waiting, useful for keeping processes seperate or multitasking

    .PARAMETER OptionalParameter1
    Type in any optional parameters that were not detected from the conversion of help, this is inputed a string during execution

    .PARAMETER OptionalParameter2
    Type in any optional parameters that were not detected from the conversion of help, this is inputed a string during execution

    .EXAMPLE
    Invoke-ConsoleApplicationWrapper -BinaryPath C:\Windows\System32 -BinaryExecutable xcopy.exe -HelpArgument '/?'

    .EXAMPLE
    Invoke-ConsoleApplicationWrapper -BinaryPath C:\temp\AZCopy -BinaryExecutable AZCopy.exe -HelpArgument '/?'

    .EXAMPLE
    Invoke-ConsoleApplicationWrapper -BinaryPath C:\Windows\System32 -BinaryExecutable Robocopy.exe -HelpArgument '/?'
    
    .NOTES
    This was originally built for AZCopy but due to PS limitations with Program Files (x86, copy AZCopy somewhere out of Program Files (x86))
    If a parameter from the legacy console application was a switch, this wrapper will assume its a string. Instead to use it as a switch during invokecation use $null for the string. e.g. "-MIR $null" for robocopy
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            HelpMessage = 'The path to the binary, the full path is highly suggested'
        )]
        [string]$BinaryPath,

        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = 'The binary name, i.e. binary.exe'
        )]
        [string]$BinaryExecutable,
        
        [Parameter(
            Mandatory = $false,
            Position = 2,
            HelpMessage = 'The switch used to access the built in help, typically /?'
        )]
        [string]$HelpArgument,

        [Parameter(
            Mandatory = $false,
            Position = 3,
            HelpMessage = 'The parameter specific spacing, most of the time a single space between the parameter and the arguement, though things like AZCopy are stupid and do /Param:Arg'
        )]
        [string]$ParameterSpacing = ' ',

        [Parameter(
            Mandatory = $false,
            Position = 4,
            HelpMessage = 'Use this switch if you want to use Start-Process in a new window for invocation'
        )]
        [switch]$SeperateWindow,

        [Parameter(
            Mandatory = $false,
            Position = 5,
            HelpMessage = 'This is an optional parameter for things like Robocopy source'
        )]
        [string]$OptionalParameter1,

        [Parameter(
            Mandatory = $false,
            Position = 6,
            HelpMessage = 'This is an optional parameter for things like Robocopy destination'
        )]
        [string]$OptionalParameter2
    )

    DynamicParam {
        if ($true) {
            do {
                Write-Verbose 'Running Convert-ConsoleApplicationHelp function'
                $ParametersInformation = Convert-ConsoleApplicationHelp -BinaryPath $PSBoundParameters.BinaryPath -BinaryExecutable $PSBoundParameters.BinaryExecutable -HelpArgument $PSBoundParameters.HelpArgument
                
                #Build the Parameter Dictionary
                $paramDictionary = New-Object -Type System.Management.Automation.RuntimeDefinedParameterDictionary
                
                #Meta Program all the things!
                for ($i = 0; $i -lt $ParametersInformation.Count; $i++) {
                    #Define the basic parameter information
                    $attributes = New-Object System.Management.Automation.ParameterAttribute
                    $attributes.ParameterSetName = "__AllParameterSets"
                    $attributes.Mandatory = $false
                    $attributes.HelpMessage = $ParametersInformation[$i].ParameterHelp
                    
                    $attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
                    $attributeCollection.Add($attributes)
                    
                    $dynParam = New-Object -Type System.Management.Automation.RuntimeDefinedParameter(
                        $ParametersInformation[$i].ParameterName,
                        [String],
                        $attributeCollection
                    )

                    $paramDictionary.Add($ParametersInformation[$i].ParameterName, $dynParam)
                }

                #Return the object for consumption
                return $paramDictionary
            }  until ($paramDictionary)
        } #End If
    }

    Begin {}
    Process {
        [System.Collections.ArrayList]$Arguments = @()

        #To Do, loop through all the optional parameters and maybe even make them dynamic for an unlimited number
        if ($OptionalParameter1) {
            $Arguments.Add("$($OptionalParameter1)") | Out-Null
        }

        if ($OptionalParameter2) {
            $Arguments.Add("$($OptionalParameter2)") | Out-Null
        }

        foreach ($Parameter in ($PSBoundParameters.GetEnumerator() | Where-Object {($PSItem.Key -notmatch "BinaryPath|BinaryExecutable|HelpArgument|ParameterSpacing|OptionalParameter|SeperateWindow")})) {
            if ($Parameter.Value) {
                Write-Verbose "Parameter $($Parameter.Key) has a value, we will use it"
                $Arguments.Add("/$($Parameter.Key)$($ParameterSpacing)$($Parameter.Value)") | Out-Null
            } else {
                Write-Verbose "Parameter $($Parameter.Key) has no value, we will make it look like a switch below"
                $Arguments.Add("/$($Parameter.Key)") | Out-Null
            }
        }
        
        Write-Verbose "$(Join-Path -Path $BinaryPath -ChildPath $BinaryExecutable)"
        Write-Verbose "$($Arguments.Trim() -join ' ')"

        #Invoke the legacy app
        if ($SeperateWindow) {
            Write-Verbose 'SeperateWindow was invoked, using Start-Process Invocation method'
            Start-Process -FilePath (Join-Path -Path $BinaryPath -ChildPath $BinaryExecutable) -ArgumentList ($Arguments -join ' ')
        } else {
            Write-Verbose 'Using legacy console invocation method'
            & "$(Join-Path -Path $BinaryPath -ChildPath $BinaryExecutable)" $Arguments
        }
    }
    End {}
}