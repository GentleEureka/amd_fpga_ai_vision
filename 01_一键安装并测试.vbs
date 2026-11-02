Option Explicit
Dim fso, shell, root, launcher
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = fso.BuildPath(root, "Install_and_Start.vbs")
If Not fso.FileExists(launcher) Then
  MsgBox "Install_and_Start.vbs was not found.", 16, "CAM1 FPGA + AI"
  WScript.Quit 1
End If
shell.Run "wscript.exe " & Chr(34) & launcher & Chr(34), 0, False
