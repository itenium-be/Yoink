# Prints "<hwnd> <processName>" for the current foreground window.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
}
"@
$h = [FgWin]::GetForegroundWindow()
$wpid = 0
[void][FgWin]::GetWindowThreadProcessId($h, [ref]$wpid)
$name = (Get-Process -Id $wpid -ErrorAction SilentlyContinue).ProcessName
Write-Output ("{0} {1}" -f [Int64]$h, $name)
