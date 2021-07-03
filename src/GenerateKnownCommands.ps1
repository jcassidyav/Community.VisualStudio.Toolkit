# -----------------------------------------------------------------------------
#
# This script is used to generate the KnownCommands.cs file which contains the 
# CommandIDs for all commands that are defined in the VSConstants (for example,
# `VSStd97CmdID`, `VSStd2KCmdID`, and so on).
# 
# This script needs access to the DTE object. The Package Manager Console
# exposes the DTE object via the `$dte` variable, so use the Package Manager 
# Console to run this script.
#
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3.0

if (-not (Get-Variable dte -ErrorAction SilentlyContinue)) {
    Write-Error "This script must be run in the Package Manager Console in Visual Studio."
    return
}

$commands = @{}

# Find all enums that define command IDs. These
# enums are nested under the VSConstants type.
$enums = [Microsoft.VisualStudio.VSConstants].GetMembers() | `
    Where-Object { $_.MemberType -eq "NestedType" } | `
    Where-Object { $_.IsEnum } | `
    Where-Object { $_.Name.EndsWith("CmdID") }

# Initialize the details about each enum value. We'll fill
# in the command name by finding the command in Visual Studio.
foreach ($enum in $enums) {
    foreach ($value in [Enum]::GetValues($enum)) {
        $key = "$($enum.GUID.ToString())|$([int]$value)"

        $commands[$key] = @{
            CommandSet     = "new Guid(`"$($enum.GUID.ToString())`")"
            CommandSetName = $enum.Name
            ID             = [int]$value
            Name           = ""
        }
    }
}

# Now step through each command and find the corresponding 
# enum member details, and store the name of the command.
foreach ($command in $dte.Commands) {
    # Skip commands without a name, because we need to use
    # the name as the property name in the generated code.
    if ($command.Name) {
        # The command's Guid property is a string,
        # so parse and re-format it so that we
        # use the same format that we used above.
        $key = "$([Guid]::Parse($command.Guid).ToString())|$($command.ID)"
        $entry = $commands[$key]

        if ($entry) {
            $entry.Name = $command.Name
        }
    }
}

$fileName = Join-Path -Path $PSScriptRoot -ChildPath "Community.VisualStudio.Toolkit.Shared/Commands/KnownCommands.cs"
$writer = New-Object -TypeName "System.IO.StreamWriter" -ArgumentList $fileName

try {
    $writer.WriteLine("// <auto-generated/>")
    $writer.WriteLine()
    $writer.WriteLine("using System;")
    $writer.WriteLine("using System.ComponentModel.Design;")
    $writer.WriteLine()
    $writer.WriteLine("namespace Community.VisualStudio.Toolkit")
    $writer.WriteLine("{")
    $writer.WriteLine("    /// <summary>Defines the command IDs for known commands.</summary>")
    $writer.WriteLine("    public static class KnownCommands")
    $writer.WriteLine("    {")

    # Define all of the GUIDs once so that we don't have to define them for each command.
    # We don't use the actual GUID constants that are defined in `VSConstants` because
    # not all command sets are available in all versions of Visual Studio.
    $guids = @{}

    foreach ($entry in ($commands.Values.GetEnumerator() | Sort-Object { $_.CommandSetName })) {
        if ($entry.Name) {
            if (-not $guids.ContainsKey($entry.CommandSet)) {
                $guidName = "_commandSet$($entry.CommandSetName)"
                $guids[$entry.CommandSet] = $guidName
                $writer.WriteLine("        private static readonly Guid $guidName = $($entry.CommandSet);")
            }
        }
    }

    $usedCommands = @{}

    foreach ($entry in ($commands.Values.GetEnumerator() | Sort-Object { $_.Name }, { $_.ID })) {
        if ($entry.Name) {
            # Some command names might be duplicated. 
            # Skip this command if we've seen it before.
            if (-not $usedCommands.ContainsKey($entry.Name)) {
                $usedCommands[$entry.Name] = 0
                $writer.WriteLine()
                $writer.WriteLine("        /// <summary>$($entry.Name)</summary>")
                $writer.WriteLine("        public static CommandID $($entry.Name.Replace(".", "_")) { get; } = new CommandID($($guids[$entry.CommandSet]), $($entry.ID));")
            }
        }
    }

    $writer.WriteLine("    }")
    $writer.WriteLine("}")

} finally {
    $writer.Dispose()
}

$dte.ItemOperations.OpenFile($fileName) | Out-Null
