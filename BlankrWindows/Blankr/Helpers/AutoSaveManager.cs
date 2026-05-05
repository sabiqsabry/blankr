using System;
using System.IO;
using System.Text;

namespace Blankr.Helpers;

public static class AutoSaveManager
{
    public static void SaveIfNeeded(string text, string? openedFilePath)
    {
        if (string.IsNullOrWhiteSpace(text))
            return;

        string path;
        if (!string.IsNullOrEmpty(openedFilePath))
        {
            path = openedFilePath;
        }
        else
        {
            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var filename = DateTime.Now.ToString("yyyy-MM-dd_HH-mm") + ".txt";
            path = Path.Combine(desktop, filename);
        }

        try
        {
            File.WriteAllText(path, text, Encoding.UTF8);
        }
        catch
        {
            // Best-effort save; swallow exceptions silently
        }
    }
}
