Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
extra = ""
For Each a In WScript.Arguments
  extra = extra & " " & a
Next
If Not fso.FolderExists(here & "\_diag") Then fso.CreateFolder(here & "\_diag")
cmd = "cmd /c powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & here & "\dsh-repair-ui.ps1""" & extra & " > """ & here & "\_diag\ui.log"" 2>&1"
sh.Run cmd, 0, False