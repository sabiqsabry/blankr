using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.Graphics;
using Windows.System;
using System;
using System.IO;
using Blankr.Helpers;

namespace Blankr;

public sealed partial class MainWindow : Window
{
    private const float DefaultFontSize = 17f;
    private const string UncheckedBox = "\u2610";  // ☐
    private const string CheckedBox   = "\u2611";  // ☑

    private string? _openedFilePath;
    private float _fontSize = DefaultFontSize;
    private bool _suppressSelectionUpdate;

    public MainWindow()
    {
        this.InitializeComponent();
        this.Title = "Blankr.";

        ResizeWindow(900, 650);

        this.Closed += OnWindowClosed;

        Editor.Loaded += OnEditorLoaded;
        Editor.SelectionChanged += OnEditorSelectionChanged;
        Editor.PreviewKeyDown += OnEditorPreviewKeyDown;
        Editor.AddHandler(UIElement.TappedEvent, new TappedEventHandler(OnEditorTapped), true);
    }

    // ---------------------------------------------------------------
    //  Public API (called from App.xaml.cs)
    // ---------------------------------------------------------------

    public void LoadFile(string path)
    {
        try
        {
            var text = File.ReadAllText(path);
            _openedFilePath = path;
            Editor.Document.SetText(TextSetOptions.None, text);
            Editor.Focus(FocusState.Programmatic);
        }
        catch { }
    }

    public void PerformSave()
    {
        AutoSaveManager.SaveIfNeeded(GetCurrentText(), _openedFilePath);
    }

    // ---------------------------------------------------------------
    //  Window helpers
    // ---------------------------------------------------------------

    private void ResizeWindow(int width, int height)
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        var appWindow = AppWindow.GetFromWindowId(windowId);
        appWindow.Resize(new SizeInt32(width, height));
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        PerformSave();
    }

    // ---------------------------------------------------------------
    //  Editor setup
    // ---------------------------------------------------------------

    private void OnEditorLoaded(object sender, RoutedEventArgs e)
    {
        ApplyDefaultFormatting();
        Editor.Focus(FocusState.Programmatic);
    }

    private void ApplyDefaultFormatting()
    {
        var sel = Editor.Document.Selection;
        sel.CharacterFormat.Size = DefaultFontSize;
        sel.CharacterFormat.Name = "Segoe UI Variable";
        sel.CharacterFormat.ForegroundColor = Windows.UI.Color.FromArgb(255, 30, 30, 30);
        sel.CharacterFormat.Bold = FormatEffect.Off;
        sel.CharacterFormat.Italic = FormatEffect.Off;
        sel.CharacterFormat.Underline = UnderlineType.None;
        sel.ParagraphFormat.Alignment = ParagraphAlignment.Left;
        _fontSize = DefaultFontSize;
    }

    private string GetCurrentText()
    {
        Editor.Document.GetText(TextGetOptions.UseCrlf, out string text);
        return text.TrimEnd('\r', '\n');
    }

    // ---------------------------------------------------------------
    //  New Note
    // ---------------------------------------------------------------

    private void NewNoteButton_Click(object sender, RoutedEventArgs e)
    {
        PerformSave();

        _openedFilePath = null;
        Editor.Document.SetText(TextSetOptions.None, "");
        ApplyDefaultFormatting();
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    // ---------------------------------------------------------------
    //  Formatting state tracking
    // ---------------------------------------------------------------

    private void OnEditorSelectionChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressSelectionUpdate) return;
        UpdateFormattingState();
    }

    private void UpdateFormattingState()
    {
        var cf = Editor.Document.Selection.CharacterFormat;

        BoldButton.IsChecked = cf.Bold == FormatEffect.On;
        ItalicButton.IsChecked = cf.Italic == FormatEffect.On;
        UnderlineButton.IsChecked = cf.Underline != UnderlineType.None;

        if (cf.Size > 0) _fontSize = cf.Size;
        FontSizeLabel.Text = ((int)_fontSize).ToString();

        var pf = Editor.Document.Selection.ParagraphFormat;
        AlignLeftButton.IsChecked = pf.Alignment == ParagraphAlignment.Left
                                    || pf.Alignment == ParagraphAlignment.Undefined;
        AlignCenterButton.IsChecked = pf.Alignment == ParagraphAlignment.Center;
        AlignRightButton.IsChecked = pf.Alignment == ParagraphAlignment.Right;

        ChecklistButton.IsChecked = IsCurrentLineChecklist();
    }

    private bool IsCurrentLineChecklist()
    {
        try
        {
            var lineRange = Editor.Document.GetRange(
                Editor.Document.Selection.StartPosition,
                Editor.Document.Selection.StartPosition);
            lineRange.Expand(TextRangeUnit.Line);
            lineRange.GetText(TextGetOptions.None, out string line);
            line = line.TrimEnd('\r', '\n');
            return line.StartsWith(UncheckedBox) || line.StartsWith(CheckedBox);
        }
        catch { return false; }
    }

    // ---------------------------------------------------------------
    //  Bold / Italic / Underline
    // ---------------------------------------------------------------

    private void BoldButton_Click(object sender, RoutedEventArgs e)
    {
        var cf = Editor.Document.Selection.CharacterFormat;
        cf.Bold = cf.Bold == FormatEffect.On ? FormatEffect.Off : FormatEffect.On;
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    private void ItalicButton_Click(object sender, RoutedEventArgs e)
    {
        var cf = Editor.Document.Selection.CharacterFormat;
        cf.Italic = cf.Italic == FormatEffect.On ? FormatEffect.Off : FormatEffect.On;
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    private void UnderlineButton_Click(object sender, RoutedEventArgs e)
    {
        var cf = Editor.Document.Selection.CharacterFormat;
        cf.Underline = cf.Underline == UnderlineType.None ? UnderlineType.Single : UnderlineType.None;
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    // ---------------------------------------------------------------
    //  Font size
    // ---------------------------------------------------------------

    private void FontSizeUpButton_Click(object sender, RoutedEventArgs e)
    {
        AdjustFontSize(1);
    }

    private void FontSizeDownButton_Click(object sender, RoutedEventArgs e)
    {
        AdjustFontSize(-1);
    }

    private void AdjustFontSize(float delta)
    {
        var cf = Editor.Document.Selection.CharacterFormat;
        float current = cf.Size > 0 ? cf.Size : _fontSize;
        float next = Math.Clamp(current + delta, 8, 96);
        cf.Size = next;
        _fontSize = next;
        FontSizeLabel.Text = ((int)_fontSize).ToString();
        Editor.Focus(FocusState.Programmatic);
    }

    // ---------------------------------------------------------------
    //  Alignment
    // ---------------------------------------------------------------

    private void AlignLeftButton_Click(object sender, RoutedEventArgs e)
    {
        Editor.Document.Selection.ParagraphFormat.Alignment = ParagraphAlignment.Left;
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    private void AlignCenterButton_Click(object sender, RoutedEventArgs e)
    {
        Editor.Document.Selection.ParagraphFormat.Alignment = ParagraphAlignment.Center;
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    private void AlignRightButton_Click(object sender, RoutedEventArgs e)
    {
        Editor.Document.Selection.ParagraphFormat.Alignment = ParagraphAlignment.Right;
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    // ---------------------------------------------------------------
    //  Checklist – insert
    // ---------------------------------------------------------------

    private void ChecklistButton_Click(object sender, RoutedEventArgs e)
    {
        InsertChecklistItem();
        UpdateFormattingState();
        Editor.Focus(FocusState.Programmatic);
    }

    private void InsertChecklistItem()
    {
        var sel = Editor.Document.Selection;
        int pos = sel.StartPosition;

        string prefix = "";
        if (pos > 0)
        {
            var prev = Editor.Document.GetRange(pos - 1, pos);
            prev.GetText(TextGetOptions.None, out string ch);
            if (ch != "\r") prefix = "\r";
        }

        string insertion = prefix + UncheckedBox + " ";
        sel.SetText(TextSetOptions.None, insertion);
        sel.Collapse(false);
    }

    // ---------------------------------------------------------------
    //  Checklist – Enter key auto-continue
    // ---------------------------------------------------------------

    private void OnEditorPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter && HandleChecklistEnter())
        {
            e.Handled = true;
        }
    }

    private bool HandleChecklistEnter()
    {
        try
        {
            var doc = Editor.Document;
            var sel = doc.Selection;
            int pos = sel.StartPosition;

            var lineRange = doc.GetRange(pos, pos);
            lineRange.Expand(TextRangeUnit.Line);
            lineRange.GetText(TextGetOptions.None, out string lineText);
            string line = lineText.TrimEnd('\r', '\n');

            bool isEmptyCheckbox = line == UncheckedBox
                                   || line == CheckedBox
                                   || line == UncheckedBox + " "
                                   || line == CheckedBox + " ";
            if (isEmptyCheckbox)
            {
                _suppressSelectionUpdate = true;
                lineRange.SetText(TextSetOptions.None, "");
                _suppressSelectionUpdate = false;
                return true;
            }

            bool startsWithCheckbox = line.StartsWith(UncheckedBox + " ")
                                      || line.StartsWith(CheckedBox + " ");
            if (startsWithCheckbox)
            {
                _suppressSelectionUpdate = true;
                string insert = "\r" + UncheckedBox + " ";
                sel.SetText(TextSetOptions.None, insert);
                sel.Collapse(false);
                _suppressSelectionUpdate = false;
                return true;
            }
        }
        catch { }

        return false;
    }

    // ---------------------------------------------------------------
    //  Checklist – click to toggle ☐ ↔ ☑
    // ---------------------------------------------------------------

    private void OnEditorTapped(object sender, TappedRoutedEventArgs e)
    {
        try
        {
            int pos = Editor.Document.Selection.StartPosition;

            for (int i = Math.Max(0, pos - 1); i <= pos + 1 && i >= 0; i++)
            {
                var range = Editor.Document.GetRange(i, i + 1);
                range.GetText(TextGetOptions.None, out string ch);

                if (ch == UncheckedBox || ch == CheckedBox)
                {
                    var fmt = range.CharacterFormat.GetClone();
                    range.SetText(TextSetOptions.None, ch == UncheckedBox ? CheckedBox : UncheckedBox);
                    range.CharacterFormat.SetClone(fmt);
                    UpdateFormattingState();
                    return;
                }
            }
        }
        catch { }
    }
}
