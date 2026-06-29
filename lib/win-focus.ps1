Add-Type @"
using System; using System.Runtime.InteropServices;
public class WinFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public const int SW_RESTORE = 9;

  [StructLayout(LayoutKind.Sequential)]
  public struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
  [DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
  // FLASHW_ALL (taskbar + caption) | FLASHW_TIMERNOFG (flash until the window comes to the foreground)
  public const uint FLASHW_ALL = 3, FLASHW_TIMERNOFG = 12;

  public static void Flash(IntPtr h) {
    FLASHWINFO fi = new FLASHWINFO();
    fi.cbSize = (uint)Marshal.SizeOf(fi);
    fi.hwnd = h; fi.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG; fi.uCount = uint.MaxValue; fi.dwTimeout = 0;
    FlashWindowEx(ref fi);
  }
}
"@
