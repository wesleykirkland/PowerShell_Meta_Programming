#Global Vars
$SectionPatterns = '::|##'
[System.Collections.ArrayList]$SectionHeaderVariables = @()
$VerbosePreference = 'Continue'

#Location of the binary file we want to scan
Set-Location 'C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy'

#Binary we want to convert
$BinaryHelpInfo = robocopy.exe /?

#Basic sanitization of the help data, removes excess lines and leading/trailing spaces
$BinaryHelpInfo = $BinaryHelpInfo | Where-Object {$_}

#Loop through the file and find the major sections of data
for ($i = 0; $i -lt $BinaryHelpInfo.Count; $i++) {
    $BinaryHelpInfoHeaderMatch = $BinaryHelpInfo[$i] -match $SectionPatterns
    #if ($i = 12) {$true} #TEMP debug

    if ($BinaryHelpInfoHeaderMatch) {
        Write-Verbose "We matched a section header on line ""$($BinaryHelpInfo[$i])""" #Quotes for character escaping

        #Set a temp variable as a indicator that we hit a section header
        $SectionHeaderLine = $true

        #Attempt to strip out the header name so we can use it later
        $HeaderNameReplaced = ($BinaryHelpInfo[$i] -replace $SectionPatterns, '').Trim()
        if ($HeaderNameReplaced) {
            Write-Verbose "Section Header Name is $HeaderNameReplaced"
            $Script:SectionHeaderName = $HeaderNameReplaced
        }
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
                        $SectionHeaderVariables.Add($SectionVariableName) | Out-Null
                    } Catch {}
                    $i = $i - 1 #Step the loop back int 1 so we don't miss the line
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
        #Populate the Section Variable with the Header Name
        if ($Script:SectionHeaderName) {
            Set-Variable -Name $SectionVariableName -Value @(
                "Header Name: $Script:SectionHeaderName"
                ''
            )
            $Script:SectionHeaderName = $null #Nullify it so we forget about it
        }

        #Populate the Section variable with content
        Set-Variable -Name $SectionVariableName -Value @(
            (Get-Variable -Name $SectionVariableName).Value #Add the existing value so we don't lose it
            $BinaryHelpInfo[$i] #Add new line info
        )
    }
}

$Section1