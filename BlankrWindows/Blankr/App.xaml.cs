using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using System;

namespace Blankr;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        this.InitializeComponent();
        this.UnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.ProcessExit += OnProcessExit;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();

        var activatedArgs = AppInstance.GetCurrent().GetActivatedEventArgs();
        if (activatedArgs.Kind == ExtendedActivationKind.File)
        {
            if (activatedArgs.Data is Windows.ApplicationModel.Activation.IFileActivatedEventArgs fileArgs
                && fileArgs.Files.Count > 0
                && fileArgs.Files[0] is Windows.Storage.StorageFile file)
            {
                (_window as MainWindow)?.LoadFile(file.Path);
            }
        }
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        (_window as MainWindow)?.PerformSave();
    }

    private void OnProcessExit(object? sender, EventArgs e)
    {
        (_window as MainWindow)?.PerformSave();
    }
}
