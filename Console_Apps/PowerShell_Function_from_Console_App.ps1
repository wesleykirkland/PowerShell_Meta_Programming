#Global Vars
$SectionPatterns = '::|##'
[System.Collections.ArrayList]$SectionHeaderVariables = @()

#Location of the binary file we want to scan
Set-Location 'C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy'

#Binary we want to convert
$BinaryHelpInfo = .\AzCopy.exe /?

#Basic sanitization of the help data, removes excess lines and leading/trailing spaces
$BinaryHelpInfo = $BinaryHelpInfo | Where-Object {$_}

#Loop through the file and find the major sections of data
for ($i = 0; $i -lt $BinaryHelpInfo.Count; $i++) {
    if ($BinaryHelpInfo[$i] -match $SectionPatterns) {
        Write-Verbose "We matched a section header on line ""$($BinaryHelpInfo[$i])""" #Quotes for character escaping

        #Set a temp variable as a indicator that we hit a section header
        $SectionHeaderLine = $true
    } elseif (($SectionHeaderLine) -and (!($BinaryHelpInfo[$i] -match $SectionPatterns))) {
        if ($SectionHeaderLine) {
            Write-Verbose "Line $i is the first line after the Section Header, were going to make a new storage var and flip a switch"

            $SectionVariableCountInt = 1
            do {
                $SectionVariableName = "Section$($SectionVariableCountInt)"
                if (!(Get-Variable $SectionVariableName -ErrorAction SilentlyContinue)) {
                    Write-Verbose "$SectionVariableCountInt is free, using that value for SectionVariableName"
                    New-Variable $SectionVariableName
                    $SectionVariableCreated = $true
                } else {
                    Write-Verbose "$SectionVariableName was taken, incrementing +1 and looping"
                    $SectionVariableCountInt++
                }
            } until ($SectionVariableCreated)
            
            $SectionHeaderLine = $false #Let PowerShell know to start storing data to the new variable
        }
        Write-Verbose "Line $i is after the section header ending, we will start processing it"
    }
}