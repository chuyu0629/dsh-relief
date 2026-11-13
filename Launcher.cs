using System;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace DshRelief {
  internal static class Program {
    [STAThread]
    private static void Main() {
      try {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DshRelief");
        Directory.CreateDirectory(dir);
        Assembly asm = Assembly.GetExecutingAssembly();
        foreach (string name in asm.GetManifestResourceNames()) {
          const string prefix = "DshRelief.";
          if (!name.StartsWith(prefix, StringComparison.Ordinal)) continue;
          string file = name.Substring(prefix.Length);
          if (file.IndexOfAny(new char[] { '\\', '/', ':' }) >= 0) continue;
          using (Stream s = asm.GetManifestResourceStream(name))
          using (FileStream o = File.Create(Path.Combine(dir, file))) { s.CopyTo(o); }
        }
        string ui = Path.Combine(dir, "dsh-repair-ui.ps1");
        if (!File.Exists(ui)) { MessageBox.Show("missing: " + ui, "DSH repair"); return; }
        var psi = new System.Diagnostics.ProcessStartInfo("powershell.exe",
          "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ui + "\"");
        psi.UseShellExecute = false;
        psi.WorkingDirectory = dir;
        System.Diagnostics.Process.Start(psi);
      } catch (Exception ex) {
        MessageBox.Show(ex.Message, "DSH repair");
      }
    }
  }
}
