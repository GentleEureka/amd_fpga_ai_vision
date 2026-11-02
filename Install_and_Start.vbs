Option Explicit
Dim fso, shell, root, scriptPath, pyw, pathParts, item, candidate, pyArgs
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(root, "host\installer_gui.py")
pyw = ""
pyArgs = ""
pathParts = Split(shell.ExpandEnvironmentStrings("%PATH%"), ";")
For Each item In pathParts
  candidate = fso.BuildPath(item, "pyw.exe")
  If fso.FileExists(candidate) Then
    pyw = candidate
    pyArgs = " -3.11 "
    Exit For
  End If
Next
If pyw = "" Then
  For Each item In pathParts
    candidate = fso.BuildPath(item, "pythonw.exe")
    If fso.FileExists(candidate) Then
      pyw = candidate
    pyArgs = " "
      Exit For
    End If
  Next
End If
If pyw = "" Then
  MsgBox "Python 3.11 was not found. Install Python 3.11 and enable the launcher, then run this file again.", 16, "CAM1 FPGA + AI"
  WScript.Quit 1
End If
shell.CurrentDirectory = root
shell.Run Chr(34) & pyw & Chr(34) & pyArgs & Chr(34) & scriptPath & Chr(34), 0, False
