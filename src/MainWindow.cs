using System;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Threading;
using System.Windows.Threading;

namespace JukeboxDownloadWizard
{
    public class MainWindow : Window
    {
private const string AppVersion = "0.3.0.0";
        private const string SsdFolderName = "ha8800_screensaver";
        private const string BitLcdArtworkFolder = "bitlcd\\thirdparty\\OneSauce";
        private const long SsdMoveReserveBytes = 1024L * 1024L * 1024L;
        private const int DefaultMinDurationSeconds = 180;
        private const int DefaultMaxDurationSeconds = 600;
        private const int MarqueeSourceFileNameLimit = 97;
        private const int MarqueeSourceFileNameWarningLength = 98;
        private const int GeneratedMarqueeFileNameLimit = 104;
        private const int GeneratedMarqueeFileNameWarningLength = 105;

        private readonly string packageRoot;
        private readonly string dataRoot;
        private readonly string assetsDir;
        private readonly string resourcesDir;
        private readonly string resourceCacheDir;
        private readonly string downloadsDir;
        private readonly string logsDir;
        private readonly string archiveLogDir;
        private readonly string consoleLogDir;
        private readonly string guiConsoleLogFile;
        private readonly string backendScript;
        private readonly string urlFile;
        private readonly string sessionStamp;
        private readonly List<Control> actionControls = new List<Control>();
        private readonly Dictionary<string, string> urlDisplayLabels = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        private Grid rootGrid;
        private TextBlock currentOperationText;
        private TextBlock operationStatusText;
        private TextBlock operationProgressText;
        private ProgressBar operationProgressBar;
        private TextBlock footerStatusText;
        private TextBlock footerVersionText;
        private TextBlock urlCountText;
        private Image rightHeaderSauceLogo;
        private TextBox urlInput;
        private Button startSearchButton;
        private int minDurationSeconds = DefaultMinDurationSeconds;
        private int maxDurationSeconds = DefaultMaxDurationSeconds;
        private TextBox minDurationHoursText;
        private TextBox minDurationMinutesText;
        private TextBox minDurationSecondsText;
        private TextBox maxDurationHoursText;
        private TextBox maxDurationMinutesText;
        private TextBox maxDurationSecondsText;
        private bool updatingDurationText;
        private Button resolution480Button;
        private Button resolution720Button;
        private Button resolution1080Button;
        private Button audioNormalizeOffButton;
        private Button audioNormalizeOnButton;
        private Button standardMarqueeOffButton;
        private Button standardMarqueeOnButton;
        private Button downloadButton;
        private int videoResolution = 720;
        private bool audioNormalizationEnabled;
        private bool standardMarqueeEnabled;
        private TextBox outputBox;
        private Window consoleWindow;
        private ListBox urlList;
        private Button cancelButton;
        private bool isRunning;
        private bool activeOperationCanCancel;
        private string activeOperationAction = "";
        private HashSet<string> activeDownloadSnapshot = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private bool activeDownloadSnapshotCaptured;
        private int lastDownloadRollbackMoveCount;
        private Process activeBackendProcess;
        private Stopwatch activeStopwatch;

        public class SearchCandidate
        {
            public bool Selected { get; set; }
            public string Artist { get; set; }
            public string Title { get; set; }
            public string Length { get; set; }
            public string Url { get; set; }
        }

        public class UrlDisplayItem
        {
            public string Url { get; set; }
            public string Display { get; set; }

            public override string ToString()
            {
                return String.IsNullOrWhiteSpace(Display) ? "Title unavailable" : Display;
            }
        }

        private class MarqueeGenerationOptions
        {
            public bool Standard { get; set; }
            public bool FullColor { get; set; }
            public bool Animated { get; set; }
        }

        private class MarqueeArtworkSource
        {
            public string TypeKey { get; set; }
            public string DisplayName { get; set; }
            public string Folder { get; set; }
            public int Count { get; set; }

            public override string ToString()
            {
                return DisplayName + " (" + Count.ToString() + " file" + (Count == 1 ? "" : "s") + ") - " + Folder;
            }
        }

        public MainWindow()
        {
            packageRoot = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            dataRoot = Path.Combine(packageRoot, ".jukebox_download_wizard");
            string devAssetsDir = Path.Combine(packageRoot, "assets");
            assetsDir = File.Exists(Path.Combine(devAssetsDir, "lib", "gui_backend.ps1")) ? devAssetsDir : Path.Combine(dataRoot, "assets");
            resourcesDir = Path.Combine(packageRoot, "resources");
            resourceCacheDir = Path.Combine(assetsDir, "resources", "cache");
            downloadsDir = Path.Combine(packageRoot, "downloads");
            logsDir = Path.Combine(packageRoot, "logs");
            archiveLogDir = Path.Combine(logsDir, "ARCHIVE_LOGS");
            consoleLogDir = logsDir;
            sessionStamp = DateTime.Now.ToString("yyyyMMddHHmmss");
            guiConsoleLogFile = Path.Combine(consoleLogDir, "gui_console_" + sessionStamp + ".log");
            backendScript = Path.Combine(assetsDir, "lib", "gui_backend.ps1");
            urlFile = Path.Combine(resourcesDir, "jukebox_urls.txt");
            HideInternalAppFolder();
            MigrateHiddenDownloadsFolder();
            MigrateHiddenLogsFolder();
            RotateArchiveLogs();

            Title = "Jukebox Download Wizard v" + AppVersion;
            Width = 960;
            MinWidth = 860;
            MinHeight = 650;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Background = Brush("#0B1020");

            string iconPath = Path.Combine(assetsDir, "images", "JukeboxDownloadWizard.ico");
            if (File.Exists(iconPath))
            {
                Icon = BitmapFrame.Create(new Uri(iconPath, UriKind.Absolute));
            }

            BuildUi();
            Closing += delegate { KillActiveBackendProcessTree(); };
            Loaded += delegate
            {
                Rect workArea = SystemParameters.WorkArea;
                Width = Math.Max(MinWidth, workArea.Width * 0.50);
                Top = workArea.Top;
                Left = workArea.Left;
                Height = workArea.Height;
                RefreshUrls();
            };
        }

        private void HideInternalAppFolder()
        {
            try
            {
                if (Directory.Exists(dataRoot))
                {
                    FileAttributes attributes = File.GetAttributes(dataRoot);
                    if ((attributes & FileAttributes.Hidden) == 0)
                    {
                        File.SetAttributes(dataRoot, attributes | FileAttributes.Hidden);
                    }
                }
            }
            catch
            {
            }
        }

        private void MigrateHiddenDownloadsFolder()
        {
            try
            {
                string oldDownloadsDir = Path.Combine(dataRoot, "downloads");
                if (!Directory.Exists(oldDownloadsDir)) { return; }

                Directory.CreateDirectory(downloadsDir);
                foreach (string oldPath in Directory.GetFiles(oldDownloadsDir, "*", SearchOption.AllDirectories))
                {
                    string relativePath = oldPath.Substring(oldDownloadsDir.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                    string newPath = Path.Combine(downloadsDir, relativePath);
                    string newParent = Path.GetDirectoryName(newPath);
                    if (!String.IsNullOrWhiteSpace(newParent)) { Directory.CreateDirectory(newParent); }
                    if (File.Exists(newPath)) { newPath = GetUniqueFilePath(newParent, Path.GetFileName(newPath)); }
                    File.Move(oldPath, newPath);
                }

                if (Directory.GetFiles(oldDownloadsDir, "*", SearchOption.AllDirectories).Length == 0)
                {
                    Directory.Delete(oldDownloadsDir, true);
                }
            }
            catch (Exception ex)
            {
                WriteOutput("Download folder migration warning: " + ex.Message);
            }
        }

        private void BuildUi()
        {
            Grid root = new Grid { Margin = new Thickness(14) };
            rootGrid = root;
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Content = root;

            Grid header = new Grid { Margin = new Thickness(0, 0, 0, 14) };
            header.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            header.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Grid.SetRow(header, 0);
            root.Children.Add(header);

            Grid topHeader = new Grid();
            topHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            topHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            topHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetRow(topHeader, 0);
            header.Children.Add(topHeader);

            Image sauceLogo = Image("one_sauce_merged.png", 176, 117, new Thickness(0, 8, 16, 0));
            Grid.SetColumn(sauceLogo, 0);
            topHeader.Children.Add(sauceLogo);

            StackPanel titleBlock = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
            Grid.SetColumn(titleBlock, 1);
            topHeader.Children.Add(titleBlock);
            titleBlock.Children.Add(Image("jukebox_download_wizard_wordmark_transparent.png", 620, 140, new Thickness(0, 0, 0, 0)));

            rightHeaderSauceLogo = Image("one_sauce_merged.png", 176, 117, new Thickness(16, 8, 0, 0));
            rightHeaderSauceLogo.HorizontalAlignment = HorizontalAlignment.Right;
            Grid.SetColumn(rightHeaderSauceLogo, 2);
            topHeader.Children.Add(rightHeaderSauceLogo);
            topHeader.SizeChanged += delegate { UpdateRightHeaderLogoVisibility(topHeader); };
            UpdateRightHeaderLogoVisibility(topHeader);

            Grid operationStatusRow = BuildOperationStatusRow();
            Grid.SetRow(operationStatusRow, 1);
            header.Children.Add(operationStatusRow);

            Grid body = new Grid();
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300), MinWidth = 300 });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 180 });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300), MinWidth = 300 });
            Grid.SetRow(body, 1);
            root.Children.Add(body);

            Border leftPanel = PanelBorder();
            Grid.SetColumn(leftPanel, 0);
            body.Children.Add(leftPanel);
            ScrollViewer leftScroller = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            StackPanel left = new StackPanel();
            leftScroller.Content = left;
            leftPanel.Child = leftScroller;
            left.Children.Add(Heading("YouTube Video Search"));
            left.Children.Add(Muted("Enter video, playlist, channel, or keywords"));
            urlInput = InputBox();
            urlInput.Margin = new Thickness(0, 4, 0, 6);
            left.Children.Add(urlInput);
            left.Children.Add(new TextBlock { Text = "Video Length (Max time = 2 hours)", FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 8, 0, 6) });
            left.Children.Add(BuildDurationFilter());
            startSearchButton = Button("Start YouTube Search", double.NaN, 42);
            startSearchButton.Margin = new Thickness(0, 8, 0, 0);
            startSearchButton.HorizontalAlignment = HorizontalAlignment.Stretch;
            startSearchButton.FontSize = 14;
            startSearchButton.FontWeight = FontWeights.SemiBold;
            startSearchButton.BorderThickness = new Thickness(2);
            startSearchButton.Padding = new Thickness(12, 6, 12, 6);
            left.Children.Add(startSearchButton);
            UpdateStartSearchButtonState();
            left.Children.Add(Separator());
            left.Children.Add(SectionTitle("Tools"));
            Button validateButton = Button("Resource Check", double.NaN, 32);
            Button showConsoleButton = Button("Show Console Window", double.NaN, 32);
            Button generateMissingMarqueesButton = Button("Generate Missing MP4 Marquees", double.NaN, 32);
            Button convertMp4ToMp3Button = Button("Create MP3s from MP4s", double.NaN, 32);
            Button viewGeneratedMarqueesButton = Button("View Generated Marquees on PC", double.NaN, 32);
            validateButton.Margin = new Thickness(0, 8, 0, 0);
            showConsoleButton.Margin = new Thickness(0, 8, 0, 0);
            generateMissingMarqueesButton.Margin = new Thickness(0, 8, 0, 0);
            convertMp4ToMp3Button.Margin = new Thickness(0, 8, 0, 0);
            viewGeneratedMarqueesButton.Margin = new Thickness(0, 8, 0, 0);
            left.Children.Add(validateButton);
            left.Children.Add(showConsoleButton);
            left.Children.Add(generateMissingMarqueesButton);
            left.Children.Add(convertMp4ToMp3Button);
            left.Children.Add(viewGeneratedMarqueesButton);
            GridSplitter leftSplitter = VerticalSplitter();
            Grid.SetColumn(leftSplitter, 1);
            body.Children.Add(leftSplitter);

            Border rightPanel = PanelBorder();
            Grid.SetColumn(rightPanel, 2);
            body.Children.Add(rightPanel);
            Grid right = new Grid();
            right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            rightPanel.Child = right;
            Grid urlHeader = new Grid { Margin = new Thickness(0, 0, 0, 8), VerticalAlignment = VerticalAlignment.Center };
            urlHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            urlHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
            urlHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            right.Children.Add(urlHeader);
            urlHeader.Children.Add(new TextBlock { Text = "Selected Videos", FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), VerticalAlignment = VerticalAlignment.Center });
            urlCountText = new TextBlock { Foreground = Brush("#9CA3AF"), VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(urlCountText, 2);
            urlHeader.Children.Add(urlCountText);
            Grid urlListHost = new Grid();
            Grid.SetRow(urlListHost, 1);
            right.Children.Add(urlListHost);
            urlList = new ListBox { Background = Brush("#0F172A"), Foreground = Brush("#E5E7EB"), BorderBrush = Brush("#334155"), FontFamily = new FontFamily("Consolas"), FontSize = 13 };
            ScrollViewer.SetHorizontalScrollBarVisibility(urlList, ScrollBarVisibility.Auto);
            ScrollViewer.SetVerticalScrollBarVisibility(urlList, ScrollBarVisibility.Auto);
            ApplyDarkScrollBars(urlList);
            urlListHost.Children.Add(urlList);
            cancelButton = RoundedButton("Cancel running YouTube process", 384, 84, 12);
            cancelButton.Background = Brush("#7F1D1D");
            cancelButton.BorderBrush = Brush("#991B1B");
            cancelButton.FontSize = 14;
            cancelButton.FontWeight = FontWeights.SemiBold;
            cancelButton.Visibility = Visibility.Collapsed;
            cancelButton.Margin = new Thickness(0);
            cancelButton.HorizontalAlignment = HorizontalAlignment.Center;
            cancelButton.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetRow(cancelButton, 1);
            Panel.SetZIndex(cancelButton, 5);
            root.Children.Add(cancelButton);

            StackPanel urlButtons = new StackPanel { Margin = new Thickness(0, 10, 0, 0), HorizontalAlignment = HorizontalAlignment.Stretch };
            Grid.SetRow(urlButtons, 2);
            right.Children.Add(urlButtons);
            Button refreshButton = Button("Refresh Video List", double.NaN, 32);
            refreshButton.Margin = new Thickness(0);
            Button updateButton = Button("Update Video List", double.NaN, 32);
            updateButton.Margin = new Thickness(0, 8, 0, 0);
            Button clearButton = Button("Clear Video List", double.NaN, 32);
            clearButton.Margin = new Thickness(0, 8, 0, 0);
            clearButton.Background = Brush("#7F1D1D");
            clearButton.BorderBrush = Brush("#991B1B");
            urlButtons.Children.Add(refreshButton);
            urlButtons.Children.Add(updateButton);
            urlButtons.Children.Add(clearButton);

            GridSplitter actionSplitter = VerticalSplitter();
            Grid.SetColumn(actionSplitter, 3);
            body.Children.Add(actionSplitter);

            Border actionPanel = PanelBorder();
            Grid.SetColumn(actionPanel, 4);
            body.Children.Add(actionPanel);
            ScrollViewer actionScroller = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            StackPanel actions = new StackPanel();
            actionScroller.Content = actions;
            actionPanel.Child = actionScroller;
            actions.Children.Add(Heading("Download Actions"));
            actions.Children.Add(new TextBlock { Text = "Choose download type, video format, audio normalization, and marquee artwork when you click Download.", TextWrapping = TextWrapping.Wrap, FontSize = 12, Foreground = Brush("#9CA3AF"), Margin = new Thickness(0, 0, 0, 12) });
            downloadButton = Button("Download...", double.NaN, 32);
            Button moveToSsdButton = Button("Move MP4s to SSD", double.NaN, 32);
            Button moveBitLcdArtworkButton = Button("Move BitLCD Artwork", double.NaN, 32);
            downloadButton.Background = Brush("#2563EB");
            downloadButton.BorderBrush = Brush("#3B82F6");
            downloadButton.FontWeight = FontWeights.SemiBold;
            downloadButton.Margin = new Thickness(0, 0, 0, 0);
            Grid moveButtons = new Grid { Margin = new Thickness(0, 8, 0, 0) };
            moveButtons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            moveButtons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            moveButtons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            moveToSsdButton.Margin = new Thickness(0);
            moveBitLcdArtworkButton.Margin = new Thickness(0);
            moveToSsdButton.Padding = new Thickness(4, 4, 4, 4);
            moveBitLcdArtworkButton.Padding = new Thickness(4, 4, 4, 4);
            Grid.SetColumn(moveToSsdButton, 0);
            Grid.SetColumn(moveBitLcdArtworkButton, 2);
            moveButtons.Children.Add(moveToSsdButton);
            moveButtons.Children.Add(moveBitLcdArtworkButton);
            actions.Children.Add(downloadButton);
            actions.Children.Add(moveButtons);
            actions.Children.Add(Separator());
            actions.Children.Add(SectionTitle("Access Resource Paths"));
            Button openResourcesButton = Button("App Resources Directory", double.NaN, 32);
            Button openDownloadsButton = Button("Open Downloads Folder on PC", double.NaN, 32);
            Button openSsdButton = Button("Open Jukebox Directory on SSD", double.NaN, 32);
            openResourcesButton.Margin = new Thickness(0, 8, 0, 0);
            openDownloadsButton.Margin = new Thickness(0, 8, 0, 0);
            openSsdButton.Margin = new Thickness(0, 8, 0, 0);
            actions.Children.Add(openResourcesButton);
            actions.Children.Add(openDownloadsButton);
            actions.Children.Add(openSsdButton);

            Grid footer = BuildFooterStatusBar();
            Grid.SetRow(footer, 2);
            root.Children.Add(footer);

            AddActionControl(validateButton);
            AddActionControl(downloadButton);
            AddActionControl(startSearchButton);
            AddActionControl(updateButton);
            AddActionControl(clearButton);
            AddActionControl(openSsdButton);
            AddActionControl(moveToSsdButton);
            AddActionControl(moveBitLcdArtworkButton);
            AddActionControl(generateMissingMarqueesButton);
            AddActionControl(convertMp4ToMp3Button);

            refreshButton.Click += delegate { RefreshUrls(); };
            updateButton.Click += delegate { UpdateUrlList(); };
            validateButton.Click += delegate { InvokeBackend(new[] { "-Action", "Validate" }, "Validating setup..."); };
            downloadButton.Click += delegate { StartDownloadVideos(); };
            cancelButton.Click += delegate { CancelOperation(); };
            startSearchButton.Click += delegate { AddUrl(); };
            urlInput.TextChanged += delegate { UpdateStartSearchButtonState(); };
            urlInput.KeyDown += delegate(object sender, KeyEventArgs e)
            {
                if (e.Key == Key.Enter)
                {
                    e.Handled = true;
                    AddUrl();
                }
            };
            clearButton.Click += delegate { ClearUrls(); };
            openResourcesButton.Click += delegate { OpenFolder(resourcesDir); };
            openDownloadsButton.Click += delegate { OpenFolder(downloadsDir); };
            openSsdButton.Click += delegate { OpenSsdContents(); };
            showConsoleButton.Click += delegate { ShowConsoleWindow(); };
            moveToSsdButton.Click += delegate { MoveToSsd(); };
            moveBitLcdArtworkButton.Click += delegate { MoveBitLcdArtwork(); };
            generateMissingMarqueesButton.Click += delegate { GenerateMissingMarquees(); };
            convertMp4ToMp3Button.Click += delegate { ConvertMp4FilesToMp3(); };
            viewGeneratedMarqueesButton.Click += delegate { OpenGeneratedMarqueesFolder(); };
        }

        private Grid BuildResolutionToggle()
        {
            Grid grid = new Grid { Margin = new Thickness(0, 0, 0, 0) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            resolution480Button = TwoLineButton("480p", "Compact");
            resolution720Button = TwoLineButton("720p", "Standard");
            resolution1080Button = TwoLineButton("1080p", "HD");
            resolution480Button.Margin = new Thickness(0);
            resolution720Button.Margin = new Thickness(0);
            resolution1080Button.Margin = new Thickness(0);
            resolution480Button.Click += delegate { SetVideoResolution(480); };
            resolution720Button.Click += delegate { SetVideoResolution(720); };
            resolution1080Button.Click += delegate { SetVideoResolution(1080); };

            Grid.SetColumn(resolution480Button, 0);
            Grid.SetColumn(resolution720Button, 2);
            Grid.SetColumn(resolution1080Button, 4);
            grid.Children.Add(resolution480Button);
            grid.Children.Add(resolution720Button);
            grid.Children.Add(resolution1080Button);
            SetVideoResolution(720);
            return grid;
        }

        private Grid BuildAudioNormalizationToggle()
        {
            Grid grid = new Grid { Margin = new Thickness(0, 0, 0, 0) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            audioNormalizeOffButton = Button("Off", double.NaN, 36);
            audioNormalizeOnButton = Button("On", double.NaN, 36);
            audioNormalizeOffButton.Margin = new Thickness(0);
            audioNormalizeOnButton.Margin = new Thickness(0);
            audioNormalizeOffButton.Click += delegate { SetAudioNormalization(false); };
            audioNormalizeOnButton.Click += delegate { SetAudioNormalization(true); };

            Grid.SetColumn(audioNormalizeOffButton, 0);
            Grid.SetColumn(audioNormalizeOnButton, 2);
            grid.Children.Add(audioNormalizeOffButton);
            grid.Children.Add(audioNormalizeOnButton);
            SetAudioNormalization(false);
            return grid;
        }
        private Grid BuildMarqueeToggle()
        {
            Grid grid = new Grid { Margin = new Thickness(0, 0, 0, 0) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            standardMarqueeOffButton = Button("Off", double.NaN, 36);
            standardMarqueeOnButton = Button("On", double.NaN, 36);
            standardMarqueeOffButton.Margin = new Thickness(0);
            standardMarqueeOnButton.Margin = new Thickness(0);
            standardMarqueeOffButton.Click += delegate { SetNoMarquee(); };
            standardMarqueeOnButton.Click += delegate { SetStandardMarquee(true); };

            Grid.SetColumn(standardMarqueeOffButton, 0);
            Grid.SetColumn(standardMarqueeOnButton, 2);
            grid.Children.Add(standardMarqueeOffButton);
            grid.Children.Add(standardMarqueeOnButton);
            SetNoMarquee();
            return grid;
        }

        private Grid BuildFooterStatusBar()
        {
            Grid footer = new Grid { Margin = new Thickness(0, 10, 0, 0), MinHeight = 26 };
            footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            footerStatusText = new TextBlock { Text = "Ready", Foreground = Brush("#9CA3AF"), FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
            footerVersionText = new TextBlock { Text = "V " + AppVersion, Foreground = Brush("#9CA3AF"), FontSize = 12, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
            Grid.SetColumn(footerVersionText, 1);
            footer.Children.Add(footerStatusText);
            footer.Children.Add(footerVersionText);
            return footer;
        }

        private StackPanel BuildDurationFilter()
        {
            StackPanel panel = new StackPanel { Margin = new Thickness(0, 0, 0, 0) };
            panel.Children.Add(BuildDurationRow("Min", true));
            panel.Children.Add(BuildDurationRow("Max", false));
            Button reset = Button("Default Video Length", Double.NaN, 30);
            reset.Margin = new Thickness(0, 2, 0, 8);
            reset.HorizontalAlignment = HorizontalAlignment.Stretch;
            reset.Click += delegate { ResetDurationDefaults(); };
            AddActionControl(reset);
            panel.Children.Add(reset);
            UpdateDurationText();
            return panel;
        }

        private void UpdateRightHeaderLogoVisibility(Grid header)
        {
            if (rightHeaderSauceLogo == null || header == null) { return; }
            rightHeaderSauceLogo.Visibility = header.ActualWidth >= 1040 ? Visibility.Visible : Visibility.Collapsed;
        }

        private Grid BuildDurationRow(string label, bool isMin)
        {
            Grid row = new Grid { Margin = new Thickness(0, 0, 0, 6) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });

            row.Children.Add(new TextBlock { Text = label, Foreground = Brush("#9CA3AF"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) });
            Grid valueGrid = new Grid();
            valueGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            valueGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
            valueGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            valueGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
            valueGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            TextBox hours = DurationPartBox("HRS", isMin);
            TextBox minutes = DurationPartBox("MINS", isMin);
            TextBox seconds = DurationPartBox("SECS", isMin);
            if (isMin)
            {
                minDurationHoursText = hours;
                minDurationMinutesText = minutes;
                minDurationSecondsText = seconds;
            }
            else
            {
                maxDurationHoursText = hours;
                maxDurationMinutesText = minutes;
                maxDurationSecondsText = seconds;
            }

            StackPanel hoursPanel = DurationPartPanel("HRS", hours);
            StackPanel minutesPanel = DurationPartPanel("MINS", minutes);
            StackPanel secondsPanel = DurationPartPanel("SECS", seconds);
            Grid.SetColumn(hoursPanel, 0);
            Grid.SetColumn(minutesPanel, 2);
            Grid.SetColumn(secondsPanel, 4);
            valueGrid.Children.Add(hoursPanel);
            valueGrid.Children.Add(minutesPanel);
            valueGrid.Children.Add(secondsPanel);
            Grid.SetColumn(valueGrid, 1);
            row.Children.Add(valueGrid);

            Button up = Button("\u25B2", 36, 28);
            Button down = Button("\u25BC", 36, 28);
            up.FontFamily = new FontFamily("Segoe UI Symbol");
            down.FontFamily = new FontFamily("Segoe UI Symbol");
            up.FontSize = 14;
            down.FontSize = 14;
            up.FontWeight = FontWeights.SemiBold;
            down.FontWeight = FontWeights.SemiBold;
            up.VerticalAlignment = VerticalAlignment.Bottom;
            down.VerticalAlignment = VerticalAlignment.Bottom;
            up.Margin = new Thickness(6, 0, 0, 0);
            down.Margin = new Thickness(4, 0, 0, 0);
            up.Click += delegate { StepDuration(isMin, 30); };
            down.Click += delegate { StepDuration(isMin, -30); };
            AddActionControl(up);
            AddActionControl(down);
            Grid.SetColumn(up, 2);
            Grid.SetColumn(down, 3);
            row.Children.Add(up);
            row.Children.Add(down);
            return row;
        }

        private StackPanel DurationPartPanel(string label, TextBox box)
        {
            StackPanel panel = new StackPanel();
            panel.Children.Add(new TextBlock { Text = label, Foreground = Brush("#9CA3AF"), FontSize = 9, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 2) });
            panel.Children.Add(box);
            return panel;
        }

        private TextBox DurationPartBox(string label, bool isMin)
        {
            TextBox box = InputBox();
            box.Height = 28;
            box.FontWeight = FontWeights.SemiBold;
            box.TextAlignment = TextAlignment.Center;
            box.VerticalContentAlignment = VerticalAlignment.Center;
            box.Margin = new Thickness(0);
            box.ToolTip = label;
            box.LostFocus += delegate { CommitDurationInput(isMin, true); };
            box.KeyDown += delegate(object sender, KeyEventArgs e)
            {
                if (e.Key == Key.Enter)
                {
                    CommitDurationInput(isMin, true);
                    Keyboard.ClearFocus();
                    e.Handled = true;
                }
                else if (e.Key == Key.Escape)
                {
                    UpdateDurationText();
                    Keyboard.ClearFocus();
                    e.Handled = true;
                }
            };
            return box;
        }

        private void StepDuration(bool isMin, int deltaSeconds)
        {
            if (isMin)
            {
                minDurationSeconds = ClampDuration(minDurationSeconds + deltaSeconds, 0, maxDurationSeconds);
                EnsureDurationGap();
            }
            else
            {
                maxDurationSeconds = ClampDuration(maxDurationSeconds + deltaSeconds, 30, 7200);
                if (minDurationSeconds > maxDurationSeconds) { minDurationSeconds = maxDurationSeconds; }
                EnsureDurationGap();
            }
            UpdateDurationText();
        }

        private void EnsureDurationGap()
        {
            if (minDurationSeconds < maxDurationSeconds) { return; }
            if (minDurationSeconds <= 7140)
            {
                maxDurationSeconds = minDurationSeconds + 60;
            }
            else
            {
                maxDurationSeconds = 7200;
                minDurationSeconds = 7140;
            }
        }

        private void ResetDurationDefaults()
        {
            minDurationSeconds = DefaultMinDurationSeconds;
            maxDurationSeconds = DefaultMaxDurationSeconds;
            UpdateDurationText();
        }

        private void CommitDurationInput(bool isMin, bool showError)
        {
            if (updatingDurationText) { return; }

            int parsedSeconds;
            if (!TryParseDurationParts(isMin, out parsedSeconds))
            {
                if (showError) { ShowAppInfo("Invalid Video Length", "Enter whole numbers in HRS, MINS, and SECS."); }
                UpdateDurationText();
                return;
            }

            int candidate = SnapDuration(parsedSeconds);
            if (isMin)
            {
                if (candidate < 0 || candidate > 7200)
                {
                    if (showError) { ShowAppInfo("Invalid Video Length", "Minimum video length must be between 0 and 2:00:00."); }
                    UpdateDurationText();
                    return;
                }
                minDurationSeconds = candidate;
                EnsureDurationGap();
            }
            else
            {
                if (candidate < 30 || candidate > 7200)
                {
                    if (showError) { ShowAppInfo("Invalid Video Length", "Maximum video length must be between 0:30 and 2:00:00."); }
                    UpdateDurationText();
                    return;
                }
                if (candidate < minDurationSeconds)
                {
                    if (showError) { ShowAppInfo("Invalid Video Length", "Maximum video length cannot be lower than the minimum video length."); }
                    UpdateDurationText();
                    return;
                }
                maxDurationSeconds = candidate;
                EnsureDurationGap();
            }

            UpdateDurationText();
        }

        private bool TryParseDurationParts(bool isMin, out int seconds)
        {
            seconds = 0;
            TextBox hoursBox = isMin ? minDurationHoursText : maxDurationHoursText;
            TextBox minutesBox = isMin ? minDurationMinutesText : maxDurationMinutesText;
            TextBox secondsBox = isMin ? minDurationSecondsText : maxDurationSecondsText;
            if (hoursBox == null || minutesBox == null || secondsBox == null) { return false; }

            int hours;
            int minutes;
            int secs;
            if (!TryParseDurationPart(hoursBox.Text, out hours)) { return false; }
            if (!TryParseDurationPart(minutesBox.Text, out minutes)) { return false; }
            if (!TryParseDurationPart(secondsBox.Text, out secs)) { return false; }
            if (hours < 0 || minutes < 0 || secs < 0) { return false; }

            seconds = hours * 3600 + minutes * 60 + secs;
            return true;
        }

        private bool TryParseDurationPart(string value, out int parsed)
        {
            parsed = 0;
            string text = (value ?? "").Trim();
            if (text.Length == 0) { return true; }
            return Int32.TryParse(text, out parsed);
        }

        private int ClampDuration(int value, int min, int max)
        {
            if (value < min) { return min; }
            if (value > max) { return max; }
            return value;
        }

        private int SnapDuration(int seconds)
        {
            if (seconds <= 0) { return 0; }
            return (int)(Math.Round(seconds / 30.0, MidpointRounding.AwayFromZero) * 30);
        }

        private void UpdateDurationText()
        {
            updatingDurationText = true;
            SetDurationPartText(true, minDurationSeconds);
            SetDurationPartText(false, maxDurationSeconds);
            updatingDurationText = false;
        }

        private void SetDurationPartText(bool isMin, int seconds)
        {
            TimeSpan time = TimeSpan.FromSeconds(seconds);
            TextBox hoursBox = isMin ? minDurationHoursText : maxDurationHoursText;
            TextBox minutesBox = isMin ? minDurationMinutesText : maxDurationMinutesText;
            TextBox secondsBox = isMin ? minDurationSecondsText : maxDurationSecondsText;
            if (hoursBox != null) { hoursBox.Text = ((int)time.TotalHours).ToString(); }
            if (minutesBox != null) { minutesBox.Text = time.Minutes.ToString("00"); }
            if (secondsBox != null) { secondsBox.Text = time.Seconds.ToString("00"); }
        }

        private string FormatDurationValue(int seconds)
        {
            TimeSpan time = TimeSpan.FromSeconds(seconds);
            if (time.TotalHours >= 1)
            {
                return String.Format("{0}:{1:00}:{2:00}", (int)time.TotalHours, time.Minutes, time.Seconds);
            }
            return String.Format("{0}:{1:00}", time.Minutes, time.Seconds);
        }

        private void SetVideoResolution(int resolution)
        {
            videoResolution = resolution == 480 || resolution == 1080 ? resolution : 720;
            if (resolution480Button == null || resolution720Button == null || resolution1080Button == null) { return; }

            bool is480 = videoResolution == 480;
            bool is720 = videoResolution == 720;
            bool is1080 = videoResolution == 1080;
            resolution480Button.Background = Brush(is480 ? "#2563EB" : "#1F2937");
            resolution480Button.BorderBrush = Brush(is480 ? "#3B82F6" : "#374151");
            resolution480Button.FontWeight = is480 ? FontWeights.SemiBold : FontWeights.Normal;
            resolution720Button.Background = Brush(is720 ? "#2563EB" : "#1F2937");
            resolution720Button.BorderBrush = Brush(is720 ? "#3B82F6" : "#374151");
            resolution720Button.FontWeight = is720 ? FontWeights.SemiBold : FontWeights.Normal;
            resolution1080Button.Background = Brush(is1080 ? "#2563EB" : "#1F2937");
            resolution1080Button.BorderBrush = Brush(is1080 ? "#3B82F6" : "#374151");
            resolution1080Button.FontWeight = is1080 ? FontWeights.SemiBold : FontWeights.Normal;
        }

        private void AddUrl()
        {
            if (String.IsNullOrWhiteSpace(urlInput.Text))
            {
                ShowAppInfo("Enter a YouTube video, playlist, channel, or search keywords first.", Title);
                return;
            }
            string url = urlInput.Text.Trim();
            if (IsSourceUrl(url))
            {
                InvokeSelectionPreview("SourcePreview", url, "Import", "Reading playlist or channel source...");
            }
            else if (IsYouTubeUrl(url))
            {
                InvokeSelectionPreview("VideoPreview", url, "Video", "Reviewing video...");
            }
            else
            {
                InvokeSelectionPreview("SearchPreview", url, "Search", "Searching YouTube...");
            }
        }

        private void UpdateStartSearchButtonState()
        {
            if (startSearchButton == null || urlInput == null) { return; }
            bool hasInput = !String.IsNullOrWhiteSpace(urlInput.Text);
            startSearchButton.Background = Brush(hasInput ? "#16A34A" : "#243044");
            startSearchButton.BorderBrush = Brush(hasInput ? "#22C55E" : "#64748B");
            startSearchButton.Foreground = Brush(hasInput ? "#FFFFFF" : "#E5E7EB");
            startSearchButton.FontWeight = FontWeights.SemiBold;
        }

        private void Search()
        {
            AddUrl();
        }

        private int GetVideoResolution()
        {
            return videoResolution;
        }

        private bool GetAudioNormalization()
        {
            return audioNormalizationEnabled;
        }

        private void SetAudioNormalization(bool enabled)
        {
            audioNormalizationEnabled = enabled;
            if (audioNormalizeOffButton == null || audioNormalizeOnButton == null) { return; }

            audioNormalizeOffButton.Background = Brush(!enabled ? "#2563EB" : "#1F2937");
            audioNormalizeOffButton.BorderBrush = Brush(!enabled ? "#3B82F6" : "#374151");
            audioNormalizeOffButton.FontWeight = !enabled ? FontWeights.SemiBold : FontWeights.Normal;
            audioNormalizeOnButton.Background = Brush(enabled ? "#16A34A" : "#1F2937");
            audioNormalizeOnButton.BorderBrush = Brush(enabled ? "#22C55E" : "#374151");
            audioNormalizeOnButton.FontWeight = enabled ? FontWeights.SemiBold : FontWeights.Normal;
            audioNormalizeOnButton.Foreground = Brush(enabled ? "#FFFFFF" : "#E5E7EB");
            audioNormalizeOffButton.Foreground = Brush("#E5E7EB");
        }
        private bool GetStandardMarquee()
        {
            return standardMarqueeEnabled;
        }

        private void SetNoMarquee()
        {
            standardMarqueeEnabled = false;
            UpdateMarqueeToggleVisuals();
            UpdateDownloadButtonText();
        }

        private void SetStandardMarquee(bool enabled)
        {
            standardMarqueeEnabled = enabled;
            UpdateMarqueeToggleVisuals();
            UpdateDownloadButtonText();
        }

        private void UpdateDownloadButtonText()
        {
            if (downloadButton == null) { return; }
            downloadButton.Content = "Download...";
        }
        private void UpdateMarqueeToggleVisuals()
        {
            if (standardMarqueeOffButton == null || standardMarqueeOnButton == null) { return; }
            StyleThreeStateButton(standardMarqueeOffButton, !standardMarqueeEnabled, "#2563EB", "#3B82F6");
            StyleThreeStateButton(standardMarqueeOnButton, standardMarqueeEnabled, "#2563EB", "#3B82F6");
        }

        private void StyleThreeStateButton(Button button, bool active, string activeColor, string activeBorder)
        {
            button.Background = Brush(active ? activeColor : "#1F2937");
            button.BorderBrush = Brush(active ? activeBorder : "#374151");
            button.FontWeight = active ? FontWeights.SemiBold : FontWeights.Normal;
            button.Foreground = Brush(active ? "#FFFFFF" : "#E5E7EB");
        }
        private string[] WithDurationFilters(string[] args)
        {
            List<string> output = new List<string>(args);
            output.Add("-MinMinutes");
            output.Add((minDurationSeconds / 60).ToString());
            output.Add("-MinSeconds");
            output.Add(minDurationSeconds.ToString());
            output.Add("-MaxMinutes");
            output.Add((maxDurationSeconds / 60).ToString());
            output.Add("-MaxSeconds");
            output.Add(maxDurationSeconds.ToString());
            return output.ToArray();
        }

        private void ClearUrls()
        {
            MessageBoxResult answer = ShowAppDialog("Clear all saved videos from the video list? This cannot be undone.", "Confirm Clear Video List", MessageBoxButton.YesNo);
            if (answer == MessageBoxResult.Yes)
            {
                InvokeBackend(new[] { "-Action", "Clear" }, "Clearing video list...");
            }
        }

        private void UpdateUrlList()
        {
            if (!File.Exists(urlFile))
            {
                ShowAppInfo("No video list was found.", "Update Video List");
                return;
            }

            ObservableCollection<UrlDisplayItem> keepItems = new ObservableCollection<UrlDisplayItem>();
            ObservableCollection<UrlDisplayItem> removeItems = new ObservableCollection<UrlDisplayItem>();
            foreach (string line in File.ReadAllLines(urlFile))
            {
                string trimmed = line.Trim();
                if (trimmed.Length == 0) { continue; }
                keepItems.Add(new UrlDisplayItem { Url = trimmed, Display = GetUrlDisplayLabel(trimmed) });
            }

            if (keepItems.Count == 0)
            {
                ShowAppInfo("The selected video list is empty.", "Update Video List");
                return;
            }

            Window dialog = new Window
            {
                Title = "Update Video List",
                Owner = this,
                Width = Math.Min(980, Math.Max(760, ActualWidth * 0.86)),
                Height = Math.Min(680, Math.Max(500, ActualHeight * 0.78)),
                MinWidth = 720,
                MinHeight = 460,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = Brush("#0B1020"),
                ShowInTaskbar = false
            };

            Grid root = new Grid { Margin = new Thickness(14) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = root;

            TextBlock heading = new TextBlock { Text = "Update selected videos", FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 0, 0, 10) };
            root.Children.Add(heading);

            Grid lists = new Grid();
            lists.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            lists.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            lists.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetRow(lists, 1);
            root.Children.Add(lists);

            ListBox keepList = BuildUrlTransferList(keepItems);
            ListBox removeList = BuildUrlTransferList(removeItems);
            Grid.SetColumn(keepList, 0);
            Grid.SetColumn(removeList, 2);

            Grid keepPanel = TransferPanel("Keep", keepList);
            Grid removePanel = TransferPanel("Remove", removeList);
            Grid.SetColumn(keepPanel, 0);
            Grid.SetColumn(removePanel, 2);
            lists.Children.Add(keepPanel);
            lists.Children.Add(removePanel);

            StackPanel arrows = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 12, 0) };
            Button moveRight = Button(">", 54, 34);
            Button moveLeft = Button("<", 54, 34);
            moveLeft.Margin = new Thickness(0, 10, 0, 0);
            arrows.Children.Add(moveRight);
            arrows.Children.Add(moveLeft);
            Grid.SetColumn(arrows, 1);
            lists.Children.Add(arrows);

            ListBox dragSource = null;
            MouseButtonEventHandler mouseDown = delegate(object sender, MouseButtonEventArgs e)
            {
                dragSource = sender as ListBox;
            };
            MouseEventHandler mouseMove = delegate(object sender, MouseEventArgs e)
            {
                ListBox source = sender as ListBox;
                if (source != null && e.LeftButton == MouseButtonState.Pressed && source.SelectedItems.Count > 0)
                {
                    DragDrop.DoDragDrop(source, "move-url-items", DragDropEffects.Move);
                }
            };
            DragEventHandler dropHandler = delegate(object sender, DragEventArgs e)
            {
                ListBox target = sender as ListBox;
                if (target == null || dragSource == null || target == dragSource) { return; }
                MoveSelectedUrlItems(dragSource, target, keepItems, removeItems);
            };
            keepList.PreviewMouseLeftButtonDown += mouseDown;
            removeList.PreviewMouseLeftButtonDown += mouseDown;
            keepList.PreviewMouseMove += mouseMove;
            removeList.PreviewMouseMove += mouseMove;
            keepList.Drop += dropHandler;
            removeList.Drop += dropHandler;

            moveRight.Click += delegate { MoveSelectedUrlItems(keepList, removeList, keepItems, removeItems); };
            moveLeft.Click += delegate { MoveSelectedUrlItems(removeList, keepList, keepItems, removeItems); };

            DockPanel footer = new DockPanel { Margin = new Thickness(0, 12, 0, 0), LastChildFill = false };
            Grid.SetRow(footer, 2);
            root.Children.Add(footer);
            TextBlock counts = new TextBlock { Foreground = Brush("#CBD5E1"), VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(counts, Dock.Left);
            footer.Children.Add(counts);
            StackPanel buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            DockPanel.SetDock(buttons, Dock.Right);
            Button ok = Button("OK", 90, 32);
            Button cancel = Button("Cancel", 90, 32);
            ok.Background = Brush("#2563EB");
            ok.BorderBrush = Brush("#3B82F6");
            ok.Margin = new Thickness(0, 0, 8, 0);
            buttons.Children.Add(ok);
            buttons.Children.Add(cancel);
            footer.Children.Add(buttons);

            Action updateCounts = delegate { counts.Text = "Keep: " + keepItems.Count.ToString() + "    Remove: " + removeItems.Count.ToString(); };
            keepItems.CollectionChanged += delegate { updateCounts(); };
            removeItems.CollectionChanged += delegate { updateCounts(); };
            updateCounts();

            ok.Click += delegate { dialog.DialogResult = true; };
            cancel.Click += delegate { dialog.DialogResult = false; };

            if (dialog.ShowDialog() == true)
            {
                List<UrlDisplayItem> sorted = new List<UrlDisplayItem>(keepItems);
                sorted.Sort(delegate(UrlDisplayItem left, UrlDisplayItem right)
                {
                    return StringComparer.OrdinalIgnoreCase.Compare(left.Display, right.Display);
                });
                List<string> keptUrls = new List<string>();
                foreach (UrlDisplayItem item in sorted) { keptUrls.Add(item.Url); }
                File.WriteAllLines(urlFile, keptUrls.ToArray(), Encoding.ASCII);
                RefreshUrls();
                ShowAppInfo("Video list updated.\n\nKept: " + keepItems.Count.ToString() + "\nRemoved: " + removeItems.Count.ToString(), "Update Video List");
            }
        }

        private void MoveToSsd()
        {
            List<SsdTarget> roots = FindSsdRoots();
            if (roots.Count == 0)
            {
                ShowAppInfo("One saUCE build not detected. All downloads remain in " + downloadsDir, "Move Downloads to SSD");
                return;
            }

            string root = roots.Count == 1 ? roots[0].Path : ChooseSsdRoot(roots);
            if (String.IsNullOrWhiteSpace(root)) { return; }

            string target = ChooseSsdFolder(root);
            if (String.IsNullOrWhiteSpace(target)) { return; }

            if (!IsPathInsideFolder(target, root))
            {
                ShowAppInfo("Choose " + SsdFolderName + " or a folder inside it.", "Move Downloads to SSD");
                return;
            }

            MessageBoxResult answer = ShowAppDialog("Move all files from downloads to this folder?\n\n" + target, "Confirm Move to SSD", MessageBoxButton.YesNo);
            if (answer == MessageBoxResult.Yes)
            {
                MoveDownloadsToSsdInteractive(target);
            }
        }

        private void MoveBitLcdArtwork()
        {
            List<SsdTarget> roots = FindBitLcdArtworkRoots();
            if (roots.Count == 0)
            {
                ShowAppInfo("BitLCD third-party artwork directory not detected. Artwork remains in " + Path.Combine(downloadsDir, "marquees"), "Move BitLCD Artwork");
                return;
            }

            MarqueeArtworkSource source = ChooseMarqueeArtworkSource();
            if (source == null || String.IsNullOrWhiteSpace(source.Folder)) { return; }

            List<string> selectedFiles = ChooseMarqueeArtworkFiles(source);
            if (selectedFiles == null) { return; }
            if (selectedFiles.Count == 0)
            {
                ShowAppInfo("Choose at least one marquee artwork file to move.", "Move BitLCD Artwork");
                return;
            }

            string root = roots.Count == 1 ? roots[0].Path : ChooseBitLcdRoot(roots);
            if (String.IsNullOrWhiteSpace(root)) { return; }

            string target = ChooseDestinationFolder(root, "Choose BitLCD Artwork Folder", "Choose the OneSauce folder or a folder inside it.");
            if (String.IsNullOrWhiteSpace(target)) { return; }

            if (!IsPathInsideFolder(target, root))
            {
                ShowAppInfo("Choose the OneSauce folder or a folder inside it.", "Move BitLCD Artwork");
                return;
            }

            MessageBoxResult answer = ShowAppDialog("Move " + selectedFiles.Count.ToString() + " " + source.DisplayName + " marquee artwork file" + (selectedFiles.Count == 1 ? "" : "s") + " from:\n\n" + source.Folder + "\n\nto this BitLCD folder?\n\n" + target, "Confirm Move BitLCD Artwork", MessageBoxButton.YesNo);
            if (answer == MessageBoxResult.Yes)
            {
                MoveBitLcdArtworkInteractive(selectedFiles, source.Folder, target);
            }
        }

        private MarqueeArtworkSource ChooseMarqueeArtworkSource()
        {
            string root = Path.Combine(downloadsDir, "marquees");
            if (!Directory.Exists(root))
            {
                ShowAppInfo("No marquee artwork folder was found. Nothing to move.", "Move BitLCD Artwork");
                return null;
            }

            List<MarqueeArtworkSource> candidates = new List<MarqueeArtworkSource>();
            foreach (string type in new[] { "standard", "full_color", "animated" })
            {
                string folder = Path.Combine(root, type);
                if (!Directory.Exists(folder)) { continue; }
                int count = Directory.GetFiles(folder, "*.jpg", SearchOption.TopDirectoryOnly).Length +
                            Directory.GetFiles(folder, "*.png", SearchOption.TopDirectoryOnly).Length +
                            Directory.GetFiles(folder, "*.mp4", SearchOption.TopDirectoryOnly).Length;
                if (count > 0)
                {
                    candidates.Add(new MarqueeArtworkSource
                    {
                        TypeKey = type,
                        DisplayName = GetMarqueeTypeDisplayName(type),
                        Folder = folder,
                        Count = count
                    });
                }
            }

            if (candidates.Count == 0)
            {
                ShowAppInfo("Marquee artwork folders are empty. Nothing to move.", "Move BitLCD Artwork");
                return null;
            }
            return ChooseMarqueeArtworkType(candidates);
        }

        private string GetMarqueeTypeDisplayName(string type)
        {
            if (String.Equals(type, "standard", StringComparison.OrdinalIgnoreCase)) { return "Standard"; }
            if (String.Equals(type, "full_color", StringComparison.OrdinalIgnoreCase)) { return "Full Color"; }
            if (String.Equals(type, "animated", StringComparison.OrdinalIgnoreCase)) { return "Animated"; }
            return type.Replace("_", " ");
        }

        private MarqueeArtworkSource ChooseMarqueeArtworkType(List<MarqueeArtworkSource> candidates)
        {
            Window dialog = new Window
            {
                Title = "Choose Marquee Type",
                Owner = this,
                Width = 680,
                Height = 340,
                MinWidth = 560,
                MinHeight = 300,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = Brush("#0B1020"),
                Foreground = Brush("#E5E7EB"),
                ShowInTaskbar = false
            };

            Grid root = new Grid { Margin = new Thickness(14) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = root;

            TextBlock header = new TextBlock
            {
                Text = "Choose one generated marquee type to move. Only one type should be uploaded to the BitLCD drive at a time.",
                Foreground = Brush("#E5E7EB"),
                TextWrapping = TextWrapping.Wrap,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 10)
            };
            root.Children.Add(header);

            ListBox list = new ListBox
            {
                Background = Brush("#0F172A"),
                Foreground = Brush("#E5E7EB"),
                BorderBrush = Brush("#334155"),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 13
            };
            foreach (MarqueeArtworkSource candidate in candidates) { list.Items.Add(candidate); }
            if (list.Items.Count > 0) { list.SelectedIndex = 0; }
            Grid.SetRow(list, 1);
            root.Children.Add(list);

            StackPanel buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
            Button ok = Button("Choose Files", 120, 32);
            Button cancel = Button("Cancel", 90, 32);
            ok.Background = Brush("#2563EB");
            ok.BorderBrush = Brush("#3B82F6");
            ok.Margin = new Thickness(0, 0, 8, 0);
            buttons.Children.Add(ok);
            buttons.Children.Add(cancel);
            Grid.SetRow(buttons, 2);
            root.Children.Add(buttons);

            MarqueeArtworkSource selected = null;
            ok.Click += delegate
            {
                selected = list.SelectedItem as MarqueeArtworkSource;
                if (selected == null)
                {
                    ShowAppInfo("Choose a marquee type.", "Choose Marquee Type", dialog);
                    return;
                }
                dialog.DialogResult = true;
            };
            cancel.Click += delegate { dialog.DialogResult = false; };
            list.MouseDoubleClick += delegate
            {
                selected = list.SelectedItem as MarqueeArtworkSource;
                if (selected != null) { dialog.DialogResult = true; }
            };

            return dialog.ShowDialog() == true ? selected : null;
        }

        private List<string> ChooseMarqueeArtworkFiles(MarqueeArtworkSource source)
        {
            List<string> files = GetMarqueeArtworkFiles(source.Folder);
            if (files.Count == 0)
            {
                ShowAppInfo(source.DisplayName + " marquee artwork folder is empty. Nothing to move.", "Move BitLCD Artwork");
                return null;
            }

            Window dialog = new Window
            {
                Title = "Choose " + source.DisplayName + " Marquee Files",
                Owner = this,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Width = Math.Min(820, Math.Max(560, ActualWidth * 0.78)),
                Height = Math.Min(740, Math.Max(460, SystemParameters.WorkArea.Height * 0.72)),
                Background = Brush("#0B1020"),
                Foreground = Brush("#E5E7EB"),
                ShowInTaskbar = false
            };

            Grid root = new Grid { Margin = new Thickness(14) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = root;

            TextBlock header = new TextBlock
            {
                Text = "Select " + source.DisplayName + " marquee artwork files to move from:\n" + source.Folder,
                Foreground = Brush("#E5E7EB"),
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 10),
                TextWrapping = TextWrapping.Wrap
            };
            root.Children.Add(header);

            StackPanel listPanel = new StackPanel();
            List<CheckBox> checkBoxes = new List<CheckBox>();
            foreach (string file in files)
            {
                FileInfo info = new FileInfo(file);
                CheckBox box = new CheckBox
                {
                    Content = Path.GetFileName(file) + "  (" + FormatBytes(info.Length) + ")",
                    Tag = file,
                    IsChecked = true,
                    Foreground = Brush("#E5E7EB"),
                    Margin = new Thickness(2, 4, 2, 4)
                };
                checkBoxes.Add(box);
                listPanel.Children.Add(box);
            }

            ScrollViewer viewer = new ScrollViewer
            {
                Content = listPanel,
                Background = Brush("#0F172A"),
                BorderBrush = Brush("#334155"),
                BorderThickness = new Thickness(1),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            ApplyDarkScrollBars(viewer);
            Grid.SetRow(viewer, 1);
            root.Children.Add(viewer);

            Grid buttons = new Grid { Margin = new Thickness(0, 12, 0, 0) };
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            Button selectAll = Button("Select All", 110, 34);
            Button deselectAll = Button("Deselect All", 120, 34);
            Button ok = Button("Move Selected", 122, 34);
            Button cancel = Button("Cancel", 100, 34);
            ok.Background = Brush("#16A34A");
            ok.BorderBrush = Brush("#22C55E");
            ok.FontWeight = FontWeights.SemiBold;
            deselectAll.Margin = new Thickness(8, 0, 0, 0);
            ok.Margin = new Thickness(0, 0, 8, 0);

            Grid.SetColumn(selectAll, 0);
            Grid.SetColumn(deselectAll, 1);
            Grid.SetColumn(ok, 3);
            Grid.SetColumn(cancel, 4);
            buttons.Children.Add(selectAll);
            buttons.Children.Add(deselectAll);
            buttons.Children.Add(ok);
            buttons.Children.Add(cancel);
            Grid.SetRow(buttons, 2);
            root.Children.Add(buttons);

            List<string> selected = null;
            selectAll.Click += delegate { foreach (CheckBox box in checkBoxes) { box.IsChecked = true; } };
            deselectAll.Click += delegate { foreach (CheckBox box in checkBoxes) { box.IsChecked = false; } };
            cancel.Click += delegate { dialog.DialogResult = false; dialog.Close(); };
            ok.Click += delegate
            {
                selected = new List<string>();
                foreach (CheckBox box in checkBoxes)
                {
                    if (box.IsChecked == true && box.Tag is string) { selected.Add((string)box.Tag); }
                }
                if (selected.Count == 0)
                {
                    ShowAppInfo("Choose at least one marquee artwork file.", "Choose Marquee Files", dialog);
                    return;
                }
                dialog.DialogResult = true;
                dialog.Close();
            };

            return dialog.ShowDialog() == true ? selected : null;
        }

        private List<string> GetMarqueeArtworkFiles(string folder)
        {
            List<string> files = new List<string>();
            if (!Directory.Exists(folder)) { return files; }
            files.AddRange(Directory.GetFiles(folder, "*.png", SearchOption.TopDirectoryOnly));
            files.AddRange(Directory.GetFiles(folder, "*.jpg", SearchOption.TopDirectoryOnly));
            files.AddRange(Directory.GetFiles(folder, "*.mp4", SearchOption.TopDirectoryOnly));
            files.Sort(StringComparer.OrdinalIgnoreCase);
            return files;
        }

        private void MoveBitLcdArtworkInteractive(List<string> selectedFiles, string sourceFolder, string target)
        {
            if (Dispatcher.CheckAccess())
            {
                activeOperationCanCancel = false;
                activeOperationAction = "MoveBitLcdArtwork";
                SetOperation("Move BitLCD Artwork", "Starting", 0);
                SetBusy(true);
                ThreadPool.QueueUserWorkItem(delegate { MoveBitLcdArtworkInteractive(selectedFiles, sourceFolder, target); });
                return;
            }

            try
            {
                activeOperationCanCancel = false;
                activeOperationAction = "MoveBitLcdArtwork";
                SetOperation("Move BitLCD Artwork", "Starting", 0);
                SetBusy(true);
                Stopwatch moveStopwatch = Stopwatch.StartNew();

                string marqueeDir = sourceFolder;
                if (!Directory.Exists(marqueeDir))
                {
                    ShowAppInfo("No marquee artwork folder was found. Nothing to move.", "Move BitLCD Artwork");
                    return;
                }

                List<string> files = new List<string>(selectedFiles);
                files.RemoveAll(delegate(string file) { return String.IsNullOrWhiteSpace(file) || !File.Exists(file) || !IsPathInsideFolder(file, marqueeDir); });
                files.Sort(StringComparer.OrdinalIgnoreCase);
                if (files.Count == 0)
                {
                    ShowAppInfo("No selected marquee artwork files were found. Nothing to move.", "Move BitLCD Artwork");
                    return;
                }

                long moveBytes = GetTotalFileBytes(files);
                DriveInfo targetDrive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(target)));
                long availableBytes = targetDrive.AvailableFreeSpace;
                if (availableBytes < moveBytes + SsdMoveReserveBytes)
                {
                    ShowAppInfo(
                        "Not enough free space on the selected BitLCD folder.\n\nFiles waiting to move: " + FormatBytes(moveBytes) +
                        "\nAvailable on drive: " + FormatBytes(availableBytes) +
                        "\nRequired reserve after move: " + FormatBytes(SsdMoveReserveBytes) +
                        "\n\nFree space on the drive or move fewer files, then try again.",
                        "Move BitLCD Artwork");
                    return;
                }
                WriteOutput("BitLCD disk space check passed. Artwork to move: " + FormatBytes(moveBytes) + ". Available: " + FormatBytes(availableBytes) + ".");

                int moved = 0;
                int renamed = 0;
                for (int i = 0; i < files.Count; i++)
                {
                    string file = files[i];
                    string fileName = Path.GetFileName(file);
                    SetOperation("Move BitLCD Artwork", "Processing " + (i + 1).ToString() + " of " + files.Count.ToString() + ": " + fileName, ((double)(i + 1) / files.Count) * 100.0);
                    long fileBytes = new FileInfo(file).Length;
                    string destination = Path.Combine(target, fileName);
                    if (File.Exists(destination))
                    {
                        MessageBoxResult choice = ShowAppDialog(
                            "Artwork already exists in the BitLCD folder:\n\n" + fileName + "\n\nYes = move with a new name\nNo = skip this file\nCancel = stop moving artwork",
                            "Duplicate Artwork Found",
                            MessageBoxButton.YesNoCancel);
                        if (choice == MessageBoxResult.Yes)
                        {
                            destination = GetUniqueFilePath(target, fileName);
                            renamed++;
                        }
                        else if (choice == MessageBoxResult.No)
                        {
                            WriteOutput("Skipped duplicate artwork: " + fileName);
                            continue;
                        }
                        else
                        {
                            WriteOutput("Move BitLCD Artwork stopped before: " + fileName);
                            return;
                        }
                    }

                    if (!HasEnoughSpaceForMove(target, fileBytes))
                    {
                        WriteOutput("Move stopped before " + fileName + ". Not enough free space remains on the BitLCD drive.");
                        ShowAppInfo("Not enough free space remains on the BitLCD drive.\n\nStopped before moving:\n" + fileName + "\n\nAlready moved artwork remains on the drive. Remaining artwork remains in " + marqueeDir + ".", "Move BitLCD Artwork");
                        return;
                    }
                    File.Move(file, destination);
                    moved++;
                    WriteOutput("Moved artwork: " + Path.GetFileName(destination));
                }
                moveStopwatch.Stop();
                WriteOutput("Finished moving " + moved.ToString() + " artwork file(s). Renamed duplicates: " + renamed.ToString() + ". Completed in " + FormatElapsed(moveStopwatch.Elapsed));
            }
            catch (Exception ex)
            {
                WriteOutput("Move BitLCD Artwork failed: " + ex.Message);
                ShowAppInfo(ex.Message, "Move BitLCD Artwork");
            }
            finally
            {
                SetBusy(false);
            }
        }
        private void MoveDownloadsToSsdInteractive(string target)
        {
            if (Dispatcher.CheckAccess())
            {
                activeOperationCanCancel = false;
                activeOperationAction = "MoveToSsd";
                SetOperation("Move to SSD", "Starting", 0);
                SetBusy(true);
                ThreadPool.QueueUserWorkItem(delegate { MoveDownloadsToSsdInteractive(target); });
                return;
            }

            try
            {
                activeOperationCanCancel = false;
                activeOperationAction = "MoveToSsd";
                SetOperation("Move to SSD", "Starting", 0);
                SetBusy(true);
                Stopwatch moveStopwatch = Stopwatch.StartNew();

                string discardDir = Path.Combine(downloadsDir, "discard");
                Directory.CreateDirectory(discardDir);
                string[] files = Directory.GetFiles(downloadsDir, "*", SearchOption.TopDirectoryOnly);
                if (files.Length == 0)
                {
                    ShowAppInfo("Downloads folder is empty. Nothing to move.", "Move Downloads to SSD");
                    return;
                }

                long moveBytes = GetTotalFileBytes(files);
                DriveInfo targetDrive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(target)));
                long availableBytes = targetDrive.AvailableFreeSpace;
                if (availableBytes < moveBytes + SsdMoveReserveBytes)
                {
                    ShowAppInfo(
                        "Not enough free space on the selected SSD folder.\n\nFiles waiting to move: " + FormatBytes(moveBytes) +
                        "\nAvailable on SSD: " + FormatBytes(availableBytes) +
                        "\nRequired reserve after move: " + FormatBytes(SsdMoveReserveBytes) +
                        "\n\nFree space on the SSD or move fewer files, then try again.",
                        "Move Downloads to SSD");
                    return;
                }
                WriteOutput("SSD disk space check passed. Files to move: " + FormatBytes(moveBytes) + ". Available: " + FormatBytes(availableBytes) + ".");

                Dictionary<string, string> targetKeys = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (string targetFile in Directory.GetFiles(target, "*", SearchOption.TopDirectoryOnly))
                {
                    targetKeys[GetFileReviewKey(Path.GetFileName(targetFile))] = Path.GetFileName(targetFile);
                }

                int moved = 0;
                int discarded = 0;
                int deleted = 0;
                for (int i = 0; i < files.Length; i++)
                {
                    string file = files[i];
                    string fileName = Path.GetFileName(file);
                    SetOperation("Move to SSD", "Processing " + (i + 1).ToString() + " of " + files.Length.ToString() + ": " + fileName, ((double)(i + 1) / files.Length) * 100.0);
                    string reviewKey = GetFileReviewKey(fileName);
                    string destination = Path.Combine(target, fileName);
                    long fileBytes = new FileInfo(file).Length;
                    bool duplicate = File.Exists(destination) || targetKeys.ContainsKey(reviewKey);
                    if (duplicate)
                    {
                        string match = targetKeys.ContainsKey(reviewKey) ? targetKeys[reviewKey] : fileName;
                        MessageBoxResult choice = ShowAppDialog(
                            "A duplicate or similar file already exists on the SSD:\n\n" + match + "\n\nFor this PC file:\n\n" + fileName + "\n\nYes = move to SSD with a new name\nNo = move to downloads\\discard\nCancel = delete from PC",
                            "Duplicate Found",
                            MessageBoxButton.YesNoCancel);
                        if (choice == MessageBoxResult.Yes)
                        {
                            destination = GetUniqueFilePath(target, fileName);
                            if (!HasEnoughSpaceForMove(target, fileBytes))
                            {
                                WriteOutput("Move stopped before " + fileName + ". Not enough free space remains on the SSD.");
                                ShowAppInfo("Not enough free space remains on the SSD.\n\nStopped before moving:\n" + fileName + "\n\nAlready moved files remain on the SSD. Remaining files remain in downloads.", "Move Downloads to SSD");
                                return;
                            }
                            File.Move(file, destination);
                            targetKeys[reviewKey] = Path.GetFileName(destination);
                            moved++;
                            WriteOutput("Moved with new name: " + Path.GetFileName(destination));
                        }
                        else if (choice == MessageBoxResult.No)
                        {
                            string discardPath = GetUniqueFilePath(discardDir, fileName);
                            File.Move(file, discardPath);
                            discarded++;
                            WriteOutput("Moved duplicate to discard: " + fileName);
                        }
                        else
                        {
                            File.Delete(file);
                            deleted++;
                            WriteOutput("Deleted duplicate from PC: " + fileName);
                        }
                        continue;
                    }

                    if (!HasEnoughSpaceForMove(target, fileBytes))
                    {
                        WriteOutput("Move stopped before " + fileName + ". Not enough free space remains on the SSD.");
                        ShowAppInfo("Not enough free space remains on the SSD.\n\nStopped before moving:\n" + fileName + "\n\nAlready moved files remain on the SSD. Remaining files remain in downloads.", "Move Downloads to SSD");
                        return;
                    }
                    File.Move(file, destination);
                    targetKeys[reviewKey] = fileName;
                    moved++;
                    WriteOutput("Moved: " + fileName);
                }
                moveStopwatch.Stop();
                WriteOutput("Finished moving " + moved.ToString() + " file(s). Duplicates discarded: " + discarded.ToString() + ". Deleted: " + deleted.ToString() + ". Completed in " + FormatElapsed(moveStopwatch.Elapsed));
            }
            catch (Exception ex)
            {
                WriteOutput("Move to SSD failed: " + ex.Message);
                ShowAppInfo(ex.Message, "Move Downloads to SSD");
            }
            finally
            {
                SetBusy(false);
            }
        }

        private bool ChooseDownloadOptions(out bool audioOnly, out int resolution, out bool normalizeAudio)
        {
            audioOnly = false;
            resolution = GetVideoResolution();
            normalizeAudio = GetAudioNormalization();
            bool selectedAudioOnly = audioOnly;
            int selectedResolution = resolution;
            bool selectedNormalizeAudio = normalizeAudio;

            Window dialog = new Window
            {
                Title = "Download Options",
                Owner = this,
                Width = 430,
                Height = 380,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                ResizeMode = ResizeMode.NoResize,
                Background = Brush("#0B1020"),
                Foreground = Brush("#E5E7EB")
            };

            StackPanel panel = new StackPanel { Margin = new Thickness(18) };
            dialog.Content = panel;
            panel.Children.Add(new TextBlock { Text = "Choose what to download:", FontWeight = FontWeights.SemiBold, Foreground = Brush("#FFFFFF"), Margin = new Thickness(0, 0, 0, 10) });

            RadioButton videoRadio = DialogRadio("MP4 video", true, "DownloadMediaType");
            RadioButton audioRadio = DialogRadio("MP3 audio", false, "DownloadMediaType");
            panel.Children.Add(videoRadio);
            panel.Children.Add(audioRadio);

            StackPanel videoOptions = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };
            panel.Children.Add(videoOptions);
            videoOptions.Children.Add(new TextBlock { Text = "Video format", FontWeight = FontWeights.SemiBold, Foreground = Brush("#FFFFFF"), Margin = new Thickness(0, 0, 0, 8) });
            StackPanel resolutionRow = new StackPanel { Orientation = Orientation.Horizontal };
            RadioButton r480 = DialogRadio("480p Compact", resolution == 480, "DownloadResolution");
            RadioButton r720 = DialogRadio("720p Standard", resolution == 720, "DownloadResolution");
            RadioButton r1080 = DialogRadio("1080p HD", resolution == 1080, "DownloadResolution");
            r480.Margin = new Thickness(0, 0, 18, 0);
            r720.Margin = new Thickness(0, 0, 18, 0);
            resolutionRow.Children.Add(r480);
            resolutionRow.Children.Add(r720);
            resolutionRow.Children.Add(r1080);
            videoOptions.Children.Add(resolutionRow);
            videoOptions.Children.Add(new TextBlock { Text = "Audio normalization", FontWeight = FontWeights.SemiBold, Foreground = Brush("#FFFFFF"), Margin = new Thickness(0, 14, 0, 8) });
            CheckBox normalizeCheck = new CheckBox { Content = "Normalize video audio", IsChecked = normalizeAudio, Foreground = Brush("#E5E7EB") };
            videoOptions.Children.Add(normalizeCheck);

            TextBlock mp3Note = new TextBlock { Text = "MP3 downloads use the best available audio. Marquee artwork can still be generated after download.", TextWrapping = TextWrapping.Wrap, Foreground = Brush("#9CA3AF"), Margin = new Thickness(0, 14, 0, 0), Visibility = Visibility.Collapsed };
            panel.Children.Add(mp3Note);

            RoutedEventHandler updateVisibility = delegate
            {
                bool isVideo = videoRadio.IsChecked == true;
                videoOptions.Visibility = isVideo ? Visibility.Visible : Visibility.Collapsed;
                mp3Note.Visibility = isVideo ? Visibility.Collapsed : Visibility.Visible;
            };
            videoRadio.Checked += updateVisibility;
            audioRadio.Checked += updateVisibility;
            updateVisibility(null, null);

            Grid buttons = new Grid { Margin = new Thickness(0, 22, 0, 0) };
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Button ok = Button("OK", double.NaN, 34);
            Button cancel = Button("Cancel", double.NaN, 34);
            ok.Background = Brush("#16A34A");
            ok.BorderBrush = Brush("#22C55E");
            Grid.SetColumn(ok, 0);
            Grid.SetColumn(cancel, 2);
            buttons.Children.Add(ok);
            buttons.Children.Add(cancel);
            panel.Children.Add(buttons);

            ok.Click += delegate
            {
                selectedAudioOnly = audioRadio.IsChecked == true;
                if (r480.IsChecked == true) { selectedResolution = 480; }
                else if (r1080.IsChecked == true) { selectedResolution = 1080; }
                else { selectedResolution = 720; }
                selectedNormalizeAudio = normalizeCheck.IsChecked == true;
                dialog.DialogResult = true;
            };
            cancel.Click += delegate { dialog.DialogResult = false; };

            bool accepted = dialog.ShowDialog() == true;
            if (accepted)
            {
                audioOnly = selectedAudioOnly;
                resolution = selectedResolution;
                normalizeAudio = selectedNormalizeAudio;
            }
            return accepted;
        }

        private RadioButton DialogRadio(string text, bool isChecked, string groupName)
        {
            return new RadioButton { Content = text, IsChecked = isChecked, GroupName = groupName, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 0, 0, 6) };
        }

        private bool ChooseMarqueeArtwork()
        {
            MessageBoxResult result = MessageBox.Show(this, "Generate standard marquee artwork after the download completes?", "Generate Marquee Artwork", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            if (result == MessageBoxResult.Cancel) { throw new OperationCanceledException(); }
            return result == MessageBoxResult.Yes;
        }

        private void StartDownloadVideos()
        {
            bool audioOnly;
            int resolution;
            bool normalizeAudio;
            if (!ChooseDownloadOptions(out audioOnly, out resolution, out normalizeAudio)) { return; }

            MarqueeGenerationOptions options = ChooseMarqueeGenerationOptions();
            if (options == null) { return; }

            if (audioOnly)
            {
                InvokeBackend(new[] { "-Action", "Download", "-DownloadMediaType", "Audio", "-NormalizeAudio", "False", "-GenerateStandardMarquee", options.Standard.ToString(), "-GenerateFullColorMarquee", "False", "-GenerateVideoMarquee", "False" }, "Downloading audio...");
            }
            else
            {
                SetVideoResolution(resolution);
                SetAudioNormalization(normalizeAudio);
                SetStandardMarquee(options.Standard);
                InvokeBackend(new[] { "-Action", "Download", "-DownloadMediaType", "Video", "-Resolution", resolution.ToString(), "-NormalizeAudio", normalizeAudio.ToString(), "-GenerateStandardMarquee", options.Standard.ToString(), "-GenerateFullColorMarquee", options.FullColor.ToString(), "-GenerateVideoMarquee", options.Animated.ToString() }, "Downloading videos...");
            }
        }
        private void GenerateMissingMarquees()
        {
            string folder = ChooseMp4Folder();
            if (String.IsNullOrWhiteSpace(folder)) { return; }

            List<string> files = new List<string>(Directory.GetFiles(folder, "*.mp4", SearchOption.TopDirectoryOnly));
            files.Sort(StringComparer.OrdinalIgnoreCase);
            if (files.Count == 0)
            {
                ShowAppInfo("No MP4 files were found in this folder.", "Generate Missing Marquees");
                return;
            }

            List<string> selected = ChooseMp4Files(folder, files, "Select videos for marquee generation", "Select MP4 videos to generate marquees for:", "Generate");
            if (selected == null || selected.Count == 0)
            {
                ShowAppInfo("No videos were selected for marquee generation.", "Generate Missing Marquees");
                return;
            }

            if (!EnsureSelectedMarqueeFileNamesWithinLimit(ref selected)) { return; }

            MarqueeGenerationOptions options = ChooseMarqueeGenerationOptions();
            if (options == null) { return; }

            string listFile = Path.Combine(Path.GetTempPath(), "jdw_marquee_selection_" + Guid.NewGuid().ToString("N") + ".txt");
            File.WriteAllLines(listFile, selected.ToArray(), Encoding.UTF8);
            InvokeBackend(new[] { "-Action", "GenerateMarquees", "-Value", listFile, "-GenerateStandardMarquee", options.Standard.ToString(), "-GenerateFullColorMarquee", options.FullColor.ToString(), "-GenerateVideoMarquee", options.Animated.ToString() }, "Generating marquees...");
        }

        private MarqueeGenerationOptions ChooseMarqueeGenerationOptions()
        {
            Window dialog = new Window
            {
                Title = "Choose Marquee Types",
                Owner = this,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Width = 560,
                Height = 380,
                MinWidth = 520,
                MinHeight = 340,
                Background = Brush("#0B1020"),
                Foreground = Brush("#E5E7EB"),
                ShowInTaskbar = false
            };

            Grid root = new Grid { Margin = new Thickness(16) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = root;

            TextBlock header = new TextBlock
            {
                Text = "Choose which marquee type(s) to generate:",
                Foreground = Brush("#E5E7EB"),
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 12)
            };
            root.Children.Add(header);

            StackPanel choices = new StackPanel { Margin = new Thickness(0, 4, 0, 0) };
            Grid.SetRow(choices, 1);
            root.Children.Add(choices);

            CheckBox standard = MarqueeTypeCheckBox("Standard", true);
            CheckBox fullColor = MarqueeTypeCheckBox("Full Color");
            CheckBox animated = MarqueeTypeCheckBox("Animated");
            choices.Children.Add(standard);
            choices.Children.Add(fullColor);
            choices.Children.Add(animated);

            TextBlock warning = new TextBlock
            {
                Text = "WARNING:  Uploading more than 1 marquee type (Standard, Full Color, Animated) for a Jukebox title to the BitLCD USB drive will cause unexpected issues and/or complete BitLCD failure.  Ensure only 1 selected marquee is selected when moving the marquee artwork to it's final destination.",
                Foreground = Brush("#FBBF24"),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 12, 0, 0),
                Visibility = Visibility.Collapsed
            };
            choices.Children.Add(warning);

            Action updateWarning = delegate
            {
                int checkedCount = 0;
                if (standard.IsChecked == true) { checkedCount++; }
                if (fullColor.IsChecked == true) { checkedCount++; }
                if (animated.IsChecked == true) { checkedCount++; }
                warning.Visibility = checkedCount > 1 ? Visibility.Visible : Visibility.Collapsed;
            };
            standard.Checked += delegate { updateWarning(); };
            standard.Unchecked += delegate { updateWarning(); };
            fullColor.Checked += delegate { updateWarning(); };
            fullColor.Unchecked += delegate { updateWarning(); };
            animated.Checked += delegate { updateWarning(); };
            animated.Unchecked += delegate { updateWarning(); };
            updateWarning();

            StackPanel buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
            Button ok = Button("Generate", 110, 34);
            Button cancel = Button("Cancel", 100, 34);
            ok.Background = Brush("#16A34A");
            ok.BorderBrush = Brush("#22C55E");
            ok.FontWeight = FontWeights.SemiBold;
            ok.Margin = new Thickness(0, 0, 8, 0);
            buttons.Children.Add(ok);
            buttons.Children.Add(cancel);
            Grid.SetRow(buttons, 3);
            root.Children.Add(buttons);

            MarqueeGenerationOptions selected = null;
            ok.Click += delegate
            {
                if (standard.IsChecked != true && fullColor.IsChecked != true && animated.IsChecked != true)
                {
                    ShowAppInfo("Choose at least one marquee type.", "Choose Marquee Types");
                    return;
                }
                selected = new MarqueeGenerationOptions
                {
                    Standard = standard.IsChecked == true,
                    FullColor = fullColor.IsChecked == true,
                    Animated = animated.IsChecked == true
                };
                dialog.DialogResult = true;
            };
            cancel.Click += delegate { dialog.DialogResult = false; };

            return dialog.ShowDialog() == true ? selected : null;
        }

        private CheckBox MarqueeTypeCheckBox(string text, bool isChecked = false)
        {
            return new CheckBox
            {
                Content = text,
                IsChecked = isChecked,
                Foreground = Brush("#E5E7EB"),
                FontSize = 14,
                Margin = new Thickness(2, 5, 2, 5)
            };
        }

        private void ConvertMp4FilesToMp3()
        {
            string folder = ChooseMp4Folder();
            if (String.IsNullOrWhiteSpace(folder)) { return; }

            List<string> files = new List<string>(Directory.GetFiles(folder, "*.mp4", SearchOption.TopDirectoryOnly));
            files.Sort(StringComparer.OrdinalIgnoreCase);
            if (files.Count == 0)
            {
                ShowAppInfo("No MP4 files were found in this folder.", "Create MP3s from MP4s");
                return;
            }

            List<string> selected = ChooseMp4Files(folder, files, "Select videos for MP3 conversion", "Select MP4 videos to convert to MP3:", "Convert");
            if (selected == null || selected.Count == 0)
            {
                ShowAppInfo("No videos were selected for MP3 conversion.", "Create MP3s from MP4s");
                return;
            }

            string listFile = Path.Combine(Path.GetTempPath(), "jdw_mp3_conversion_selection_" + Guid.NewGuid().ToString("N") + ".txt");
            File.WriteAllLines(listFile, selected.ToArray(), Encoding.UTF8);
            InvokeBackend(new[] { "-Action", "ConvertMp4ToMp3", "-Value", listFile }, "Converting MP4s to MP3...");
        }
        private void OpenGeneratedMarqueesFolder()
        {
            string marqueeDir = Path.Combine(downloadsDir, "marquees");
            if (!Directory.Exists(marqueeDir))
            {
                Directory.CreateDirectory(marqueeDir);
            }
            OpenFolder(marqueeDir);
        }

        private string ChooseMp4Folder()
        {
            using (System.Windows.Forms.FolderBrowserDialog dialog = new System.Windows.Forms.FolderBrowserDialog())
            {
                string defaultFolder = downloadsDir;
                if (!Directory.Exists(defaultFolder))
                {
                    Directory.CreateDirectory(defaultFolder);
                }

                dialog.Description = "Choose a folder containing MP4 files";
                dialog.RootFolder = Environment.SpecialFolder.Desktop;
                dialog.SelectedPath = defaultFolder;
                dialog.ShowNewFolderButton = false;
                System.Windows.Forms.DialogResult result = dialog.ShowDialog();
                return result == System.Windows.Forms.DialogResult.OK ? dialog.SelectedPath : "";
            }
        }
        private List<string> ChooseMp4Files(string folder, List<string> files, string title, string prompt, string okLabel)
        {
            Window dialog = new Window
            {
                Title = title,
                Owner = this,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Width = Math.Min(760, Math.Max(520, ActualWidth * 0.75)),
                Height = Math.Min(720, Math.Max(460, SystemParameters.WorkArea.Height * 0.70)),
                Background = Brush("#0B1020"),
                Foreground = Brush("#E5E7EB"),
                ShowInTaskbar = false
            };

            Grid root = new Grid { Margin = new Thickness(14) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = root;

            TextBlock header = new TextBlock
            {
                Text = prompt + "\n" + folder,
                Foreground = Brush("#E5E7EB"),
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 10),
                TextWrapping = TextWrapping.Wrap
            };
            root.Children.Add(header);

            StackPanel listPanel = new StackPanel();
            List<CheckBox> checkBoxes = new List<CheckBox>();
            foreach (string file in files)
            {
                CheckBox box = new CheckBox
                {
                    Content = Path.GetFileName(file),
                    Tag = file,
                    IsChecked = true,
                    Foreground = Brush("#E5E7EB"),
                    Margin = new Thickness(2, 4, 2, 4)
                };
                checkBoxes.Add(box);
                listPanel.Children.Add(box);
            }

            ScrollViewer viewer = new ScrollViewer
            {
                Content = listPanel,
                Background = Brush("#0F172A"),
                BorderBrush = Brush("#334155"),
                BorderThickness = new Thickness(1),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            ApplyDarkScrollBars(viewer);
            Grid.SetRow(viewer, 1);
            root.Children.Add(viewer);

            Grid buttons = new Grid { Margin = new Thickness(0, 12, 0, 0) };
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            Button selectAll = Button("Select All", 110, 34);
            Button deselectAll = Button("Deselect All", 120, 34);
            Button ok = Button(okLabel, 110, 34);
            Button cancel = Button("Cancel", 100, 34);
            ok.Background = Brush("#16A34A");
            ok.BorderBrush = Brush("#22C55E");
            ok.FontWeight = FontWeights.SemiBold;
            deselectAll.Margin = new Thickness(8, 0, 0, 0);
            ok.Margin = new Thickness(0, 0, 8, 0);

            Grid.SetColumn(selectAll, 0);
            Grid.SetColumn(deselectAll, 1);
            Grid.SetColumn(ok, 3);
            Grid.SetColumn(cancel, 4);
            buttons.Children.Add(selectAll);
            buttons.Children.Add(deselectAll);
            buttons.Children.Add(ok);
            buttons.Children.Add(cancel);
            Grid.SetRow(buttons, 2);
            root.Children.Add(buttons);

            List<string> selected = null;
            selectAll.Click += delegate { foreach (CheckBox box in checkBoxes) { box.IsChecked = true; } };
            deselectAll.Click += delegate { foreach (CheckBox box in checkBoxes) { box.IsChecked = false; } };
            cancel.Click += delegate { dialog.DialogResult = false; dialog.Close(); };
            ok.Click += delegate
            {
                selected = new List<string>();
                foreach (CheckBox box in checkBoxes)
                {
                    if (box.IsChecked == true && box.Tag is string) { selected.Add((string)box.Tag); }
                }
                dialog.DialogResult = true;
                dialog.Close();
            };

            bool? result = dialog.ShowDialog();
            return result == true ? selected : null;
        }

        private bool EnsureSelectedMarqueeFileNamesWithinLimit(ref List<string> selected)
        {
            List<Tuple<string, string>> plannedRenames = new List<Tuple<string, string>>();
            Dictionary<string, string> renamedPaths = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (string file in selected)
            {
                string fileName = Path.GetFileName(file);
                bool existingMarqueeSource = IsExistingMarqueeMp4Source(file);
                int warningLength = existingMarqueeSource ? GeneratedMarqueeFileNameWarningLength : MarqueeSourceFileNameWarningLength;
                if (String.IsNullOrWhiteSpace(fileName) || fileName.Length < warningLength) { continue; }
                string newPath = existingMarqueeSource ? GetShortenedMarqueeMp4Path(file, GeneratedMarqueeFileNameLimit) : GetShortenedMp4Path(file, MarqueeSourceFileNameLimit);
                if (String.Equals(file, newPath, StringComparison.OrdinalIgnoreCase)) { continue; }
                plannedRenames.Add(Tuple.Create(file, newPath));
            }

            if (plannedRenames.Count == 0) { return true; }

            StringBuilder message = new StringBuilder();
            message.AppendLine("One or more selected MP4 filenames are too long for reliable BitLCD marquee matching.");
            message.AppendLine();
            message.AppendLine("The app can shorten these MP4 filenames before generating marquees. Music video sources use " + MarqueeSourceFileNameLimit.ToString() + " characters including .mp4; existing animated marquee sources use " + GeneratedMarqueeFileNameLimit.ToString() + " characters including .mp4 and keep the trailing (JUKE).");
            message.AppendLine();
            int shown = 0;
            foreach (Tuple<string, string> rename in plannedRenames)
            {
                if (shown >= 10) { break; }
                message.AppendLine(Path.GetFileName(rename.Item1));
                message.AppendLine("  -> " + Path.GetFileName(rename.Item2));
                message.AppendLine();
                shown++;
            }
            if (plannedRenames.Count > shown)
            {
                message.AppendLine("...and " + (plannedRenames.Count - shown).ToString() + " more file(s).");
                message.AppendLine();
            }
            message.AppendLine("Proceed with shortening these filenames?");

            MessageBoxResult answer = ShowAppDialog(message.ToString(), "Filename Over Limit", MessageBoxButton.YesNo);
            if (answer != MessageBoxResult.Yes) { return false; }

            try
            {
                foreach (Tuple<string, string> rename in plannedRenames)
                {
                    if (!File.Exists(rename.Item1)) { continue; }
                    string newPath = rename.Item2;
                    if (!String.Equals(rename.Item1, newPath, StringComparison.OrdinalIgnoreCase) && File.Exists(newPath))
                    {
                        newPath = GetShortenedUniqueFilePath(rename.Item1, MarqueeSourceFileNameLimit);
                    }
                    if (String.Equals(rename.Item1, newPath, StringComparison.OrdinalIgnoreCase)) { continue; }
                    File.Move(rename.Item1, newPath);
                    renamedPaths[rename.Item1] = newPath;
                }

                for (int i = 0; i < selected.Count; i++)
                {
                    string newPath;
                    if (renamedPaths.TryGetValue(selected[i], out newPath)) { selected[i] = newPath; }
                }
                return true;
            }
            catch (Exception ex)
            {
                ShowAppInfo("Unable to shorten one or more MP4 filenames.\n\n" + ex.Message, "Filename Over Limit");
                return false;
            }
        }

        private string GetShortenedMp4Path(string path, int maxFileNameLength)
        {
            string folder = Path.GetDirectoryName(path) ?? "";
            string extension = Path.GetExtension(path);
            string baseName = Path.GetFileNameWithoutExtension(path);
            int maxBaseLength = Math.Max(1, maxFileNameLength - extension.Length);
            if (baseName.Length > maxBaseLength) { baseName = baseName.Substring(0, maxBaseLength).Trim(' ', '.', '_', '-'); }
            if (String.IsNullOrWhiteSpace(baseName)) { baseName = "video"; }
            string newPath = Path.Combine(folder, baseName + extension);
            if (String.Equals(path, newPath, StringComparison.OrdinalIgnoreCase)) { return path; }
            if (!File.Exists(newPath)) { return newPath; }
            return GetShortenedUniqueFilePath(path, maxFileNameLength);
        }

        private string GetShortenedMarqueeMp4Path(string path, int maxFileNameLength)
        {
            string folder = Path.GetDirectoryName(path) ?? "";
            string extension = Path.GetExtension(path);
            string baseName = Path.GetFileNameWithoutExtension(path);
            const string suffix = " (JUKE)";
            if (baseName.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
            {
                baseName = baseName.Substring(0, baseName.Length - suffix.Length).Trim(' ', '.', '_', '-');
            }
            int maxBaseLength = Math.Max(1, maxFileNameLength - extension.Length - suffix.Length);
            if (baseName.Length > maxBaseLength) { baseName = baseName.Substring(0, maxBaseLength).Trim(' ', '.', '_', '-'); }
            if (String.IsNullOrWhiteSpace(baseName)) { baseName = "marquee"; }
            string newPath = Path.Combine(folder, baseName + suffix + extension);
            if (String.Equals(path, newPath, StringComparison.OrdinalIgnoreCase)) { return path; }
            if (!File.Exists(newPath)) { return newPath; }
            return GetShortenedUniqueMarqueeFilePath(path, maxFileNameLength);
        }

        private string GetShortenedUniqueMarqueeFilePath(string path, int maxFileNameLength)
        {
            string folder = Path.GetDirectoryName(path) ?? "";
            string extension = Path.GetExtension(path);
            string originalBase = Path.GetFileNameWithoutExtension(path);
            const string marker = " (JUKE)";
            if (originalBase.EndsWith(marker, StringComparison.OrdinalIgnoreCase))
            {
                originalBase = originalBase.Substring(0, originalBase.Length - marker.Length).Trim(' ', '.', '_', '-');
            }
            for (int index = 1; index < 10000; index++)
            {
                string suffix = " (" + index.ToString() + ")" + marker;
                int maxBaseLength = Math.Max(1, maxFileNameLength - extension.Length - suffix.Length);
                string baseName = originalBase;
                if (baseName.Length > maxBaseLength) { baseName = baseName.Substring(0, maxBaseLength).Trim(' ', '.', '_', '-'); }
                if (String.IsNullOrWhiteSpace(baseName)) { baseName = "marquee"; }
                string candidate = Path.Combine(folder, baseName + suffix + extension);
                if (String.Equals(path, candidate, StringComparison.OrdinalIgnoreCase) || !File.Exists(candidate)) { return candidate; }
            }
            throw new IOException("Could not find an available shortened filename for " + Path.GetFileName(path));
        }

        private bool IsExistingMarqueeMp4Source(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) { return false; }
            if (!String.Equals(Path.GetExtension(path), ".mp4", StringComparison.OrdinalIgnoreCase)) { return false; }
            string baseName = Path.GetFileNameWithoutExtension(path);
            return (!String.IsNullOrWhiteSpace(baseName) && baseName.EndsWith(" (JUKE)", StringComparison.OrdinalIgnoreCase));
        }

        private string GetShortenedUniqueFilePath(string path, int maxFileNameLength)
        {
            string folder = Path.GetDirectoryName(path) ?? "";
            string extension = Path.GetExtension(path);
            string originalBase = Path.GetFileNameWithoutExtension(path);
            for (int index = 1; index < 10000; index++)
            {
                string suffix = " (" + index.ToString() + ")";
                int maxBaseLength = Math.Max(1, maxFileNameLength - extension.Length - suffix.Length);
                string baseName = originalBase;
                if (baseName.Length > maxBaseLength) { baseName = baseName.Substring(0, maxBaseLength).Trim(' ', '.', '_', '-'); }
                if (String.IsNullOrWhiteSpace(baseName)) { baseName = "video"; }
                string candidate = Path.Combine(folder, baseName + suffix + extension);
                if (String.Equals(path, candidate, StringComparison.OrdinalIgnoreCase) || !File.Exists(candidate)) { return candidate; }
            }
            throw new IOException("Could not find an available shortened filename for " + Path.GetFileName(path));
        }

        private void OpenSsdContents()
        {
            List<SsdTarget> roots = FindSsdRoots();
            if (roots.Count == 0)
            {
                ShowAppInfo("The " + SsdFolderName + " directory on the SSD was not found.", "Open SSD Contents");
                return;
            }

            string root = roots.Count == 1 ? roots[0].Path : ChooseSsdRoot(roots);
            if (String.IsNullOrWhiteSpace(root)) { return; }
            Process.Start("explorer.exe", "\"" + root + "\"");
        }

        private Grid TransferPanel(string title, ListBox list)
        {
            Grid panel = new Grid();
            panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            panel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            panel.Children.Add(new TextBlock { Text = title, FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 0, 0, 8) });
            Grid.SetRow(list, 1);
            panel.Children.Add(list);
            return panel;
        }

        private ListBox BuildUrlTransferList(System.Collections.IEnumerable items)
        {
            ListBox list = new ListBox
            {
                ItemsSource = items,
                SelectionMode = SelectionMode.Extended,
                AllowDrop = true,
                Background = Brush("#0F172A"),
                Foreground = Brush("#E5E7EB"),
                BorderBrush = Brush("#334155"),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 13,
                MinHeight = 320
            };
            ScrollViewer.SetHorizontalScrollBarVisibility(list, ScrollBarVisibility.Auto);
            ScrollViewer.SetVerticalScrollBarVisibility(list, ScrollBarVisibility.Auto);
            ApplyDarkScrollBars(list);
            return list;
        }

        private void MoveSelectedUrlItems(ListBox source, ListBox target, ObservableCollection<UrlDisplayItem> keepItems, ObservableCollection<UrlDisplayItem> removeItems)
        {
            if (source == null || target == null || source.SelectedItems.Count == 0) { return; }

            ObservableCollection<UrlDisplayItem> sourceItems = source.ItemsSource == keepItems ? keepItems : removeItems;
            ObservableCollection<UrlDisplayItem> targetItems = target.ItemsSource == keepItems ? keepItems : removeItems;
            List<UrlDisplayItem> moving = new List<UrlDisplayItem>();
            foreach (object selected in source.SelectedItems)
            {
                UrlDisplayItem item = selected as UrlDisplayItem;
                if (item != null) { moving.Add(item); }
            }
            foreach (UrlDisplayItem item in moving)
            {
                sourceItems.Remove(item);
                targetItems.Add(item);
            }
            source.SelectedItems.Clear();
        }

        private List<SsdTarget> FindSsdRoots()
        {
            List<SsdTarget> roots = new List<SsdTarget>();
            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (!drive.IsReady) { continue; }
                    string path = Path.Combine(drive.RootDirectory.FullName, SsdFolderName);
                    string normalized = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                    if (Directory.Exists(normalized) && !seen.Contains(normalized))
                    {
                        string label = String.IsNullOrWhiteSpace(drive.VolumeLabel) ? "No Label" : drive.VolumeLabel;
                        roots.Add(new SsdTarget(normalized, String.Format("{0} ({1}) - {2}", drive.Name.TrimEnd('\\'), label, normalized)));
                        seen.Add(normalized);
                    }
                }
                catch
                {
                }
            }
            return roots;
        }

        private List<SsdTarget> FindBitLcdArtworkRoots()
        {
            List<SsdTarget> roots = new List<SsdTarget>();
            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (!drive.IsReady) { continue; }
                    string path = Path.Combine(drive.RootDirectory.FullName, BitLcdArtworkFolder);
                    string normalized = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                    if (Directory.Exists(normalized) && !seen.Contains(normalized))
                    {
                        string label = String.IsNullOrWhiteSpace(drive.VolumeLabel) ? "No Label" : drive.VolumeLabel;
                        roots.Add(new SsdTarget(normalized, String.Format("{0} ({1}) - {2}", drive.Name.TrimEnd('\\'), label, normalized)));
                        seen.Add(normalized);
                    }
                }
                catch
                {
                }
            }
            return roots;
        }

        private string ChooseBitLcdRoot(List<SsdTarget> roots)
        {
            return ChooseRootFromTargets(roots, "Choose BitLCD Artwork Drive", "More than one bitlcd\\thirdparty\\OneSauce folder was found. Choose the drive to use.");
        }
        private string ChooseSsdRoot(List<SsdTarget> roots)
        {
            return ChooseRootFromTargets(roots, "Choose SSD Drive", "More than one " + SsdFolderName + " folder was found. Choose the drive to use.");
        }

        private string ChooseRootFromTargets(List<SsdTarget> roots, string title, string message)
        {
            Window dialog = new Window
            {
                Title = title,
                Owner = this,
                Width = 560,
                Height = 300,
                MinWidth = 480,
                MinHeight = 260,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = Brush("#0B1020")
            };

            Grid rootGrid = new Grid { Margin = new Thickness(14) };
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = rootGrid;

            rootGrid.Children.Add(new TextBlock { Text = message, Foreground = Brush("#E5E7EB"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) });

            ListBox list = new ListBox { Background = Brush("#0F172A"), Foreground = Brush("#E5E7EB"), BorderBrush = Brush("#334155"), FontFamily = new FontFamily("Consolas"), FontSize = 13 };
            foreach (SsdTarget candidate in roots) { list.Items.Add(candidate); }
            if (list.Items.Count > 0) { list.SelectedIndex = 0; }
            Grid.SetRow(list, 1);
            rootGrid.Children.Add(list);

            StackPanel buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
            Button cancelButton = Button("Cancel", 90, 30);
            Button useButton = Button("Use Selected", 122, 30);
            useButton.Background = Brush("#2563EB");
            useButton.BorderBrush = Brush("#3B82F6");
            buttons.Children.Add(cancelButton);
            buttons.Children.Add(useButton);
            Grid.SetRow(buttons, 2);
            rootGrid.Children.Add(buttons);

            string selected = null;
            useButton.Click += delegate
            {
                SsdTarget target = list.SelectedItem as SsdTarget;
                if (target != null)
                {
                    selected = target.Path;
                    dialog.DialogResult = true;
                }
            };
            cancelButton.Click += delegate { dialog.DialogResult = false; };
            list.MouseDoubleClick += delegate
            {
                SsdTarget target = list.SelectedItem as SsdTarget;
                if (target != null)
                {
                    selected = target.Path;
                    dialog.DialogResult = true;
                }
            };

            return dialog.ShowDialog() == true ? selected : null;
        }
        private class SsdTarget
        {
            public string Path { get; private set; }
            private readonly string label;

            public SsdTarget(string path, string label)
            {
                Path = path;
                this.label = label;
            }

            public override string ToString()
            {
                return label;
            }
        }

        private string ChooseSsdFolder(string startPath)
        {
            return ChooseDestinationFolder(startPath, "Choose Destination Folder", "Choose " + SsdFolderName + " or a folder inside it.");
        }

        private string ChooseDestinationFolder(string startPath, string title, string message)
        {
            List<string> destinations = GetDestinationFolders(startPath);
            Window dialog = new Window
            {
                Title = title,
                Owner = this,
                Width = 640,
                Height = 360,
                MinWidth = 520,
                MinHeight = 280,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = Brush("#0B1020")
            };

            Grid rootGrid = new Grid { Margin = new Thickness(14) };
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = rootGrid;

            rootGrid.Children.Add(new TextBlock { Text = message + " Found " + destinations.Count + " folder(s) under " + startPath + ".", Foreground = Brush("#E5E7EB"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) });

            ListBox list = new ListBox { Background = Brush("#0F172A"), Foreground = Brush("#E5E7EB"), BorderBrush = Brush("#334155"), FontFamily = new FontFamily("Consolas"), FontSize = 13 };
            foreach (string candidate in destinations)
            {
                list.Items.Add(candidate);
            }
            if (list.Items.Count > 0) { list.SelectedIndex = 0; }
            Grid.SetRow(list, 1);
            rootGrid.Children.Add(list);

            StackPanel buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
            Button cancelButton = Button("Cancel", 90, 30);
            Button useButton = Button("Use Selected", 122, 30);
            useButton.Background = Brush("#2563EB");
            useButton.BorderBrush = Brush("#3B82F6");
            buttons.Children.Add(cancelButton);
            buttons.Children.Add(useButton);
            Grid.SetRow(buttons, 2);
            rootGrid.Children.Add(buttons);

            string selected = null;
            useButton.Click += delegate
            {
                selected = list.SelectedItem as string;
                if (!String.IsNullOrWhiteSpace(selected)) { dialog.DialogResult = true; }
            };
            cancelButton.Click += delegate { dialog.DialogResult = false; };
            list.MouseDoubleClick += delegate
            {
                selected = list.SelectedItem as string;
                if (!String.IsNullOrWhiteSpace(selected)) { dialog.DialogResult = true; }
            };

            return dialog.ShowDialog() == true ? selected : null;
        }

        private List<string> GetDestinationFolders(string root)
        {
            List<string> folders = new List<string>();
            Queue<string> pending = new Queue<string>();
            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            folders.Add(root);
            pending.Enqueue(root);
            seen.Add(root);

            try
            {
                while (pending.Count > 0)
                {
                    string current = pending.Dequeue();
                    string[] children = new string[0];
                    try
                    {
                        children = Directory.GetDirectories(current);
                    }
                    catch
                    {
                        continue;
                    }

                    foreach (string child in children)
                    {
                        string normalized = Path.GetFullPath(child).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                        if (seen.Contains(normalized)) { continue; }
                        folders.Add(normalized);
                        pending.Enqueue(normalized);
                        seen.Add(normalized);
                    }
                }
            }
            catch
            {
            }
            return folders;
        }

        private bool IsPathInsideFolder(string path, string folder)
        {
            try
            {
                string fullPath = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                string fullFolder = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                return fullPath.Equals(fullFolder, StringComparison.OrdinalIgnoreCase) ||
                       fullPath.StartsWith(fullFolder + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
                       fullPath.StartsWith(fullFolder + Path.AltDirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }

        private void InvokeBackend(string[] args, string busyText)
        {
            if (isRunning)
            {
                ShowAppInfo("A task is already running.", Title);
                return;
            }

            string label = FormatCommand(args);
            string action = ArgValue(args, "-Action");
            activeOperationAction = action;
            if (action == "Download")
            {
                CaptureDownloadSnapshot();
            }
            else
            {
                activeDownloadSnapshot.Clear();
                activeDownloadSnapshotCaptured = false;
            }
            SetOperation(FormatOperationName(args), "Running", 0);
            activeOperationCanCancel = CanCancelOperation(args);
            MoveFocus(new TraversalRequest(FocusNavigationDirection.Next));
            SetBusy(true);
            WriteOutput(label);
            if (!activeOperationCanCancel)
            {
                WriteOutput("This operation cannot be cancelled while files are being moved.");
            }
            activeStopwatch = Stopwatch.StartNew();

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.WorkingDirectory = assetsDir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.EnvironmentVariables["JUKEBOX_GUI_SESSION_STAMP"] = sessionStamp;
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + backendScript + "\" " + QuoteArgs(args);

            Process process = new Process();
            process.StartInfo = psi;
            process.EnableRaisingEvents = true;
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (!HandleProgressLine(e.Data)) { WriteOutput(e.Data); }
                }));
            };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) Dispatcher.BeginInvoke(new Action(delegate { WriteOutput(e.Data); }));
            };
            process.Exited += delegate
            {
                int exitCode = process.ExitCode;
                if (activeBackendProcess != null && activeBackendProcess.Id == process.Id) { activeBackendProcess = null; }
                process.Dispose();
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    RefreshUrls();
                    SetOperation(FormatOperationName(args), exitCode == 0 ? "Done" : "Finished with errors", 100);
                    if (action == "Download" && exitCode != 0)
                    {
                        RestoreGuiDownloadSnapshot();
                    }
                    if (action == "Download" && exitCode == 0)
                    {
                        activeDownloadSnapshot.Clear();
                        activeDownloadSnapshotCaptured = false;
                    }
                    TimeSpan elapsed = activeStopwatch == null ? TimeSpan.Zero : activeStopwatch.Elapsed;
                    WriteOutput((exitCode == 0 ? "Completed" : "Finished with errors") + " in " + FormatElapsed(elapsed));
                    activeStopwatch = null;
                    SetBusy(false);
                }));
            };
            try
            {
                process.Start();
                activeBackendProcess = process;
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                WriteOutput(ex.Message);
                SetOperation(FormatOperationName(args), "Error", 100);
                activeBackendProcess = null;
                SetBusy(false);
            }
        }

        private void InvokeSelectionPreview(string actionName, string inputValue, string operationName, string startMessage)
        {
            if (isRunning)
            {
                ShowAppInfo("A task is already running.", Title);
                return;
            }

            string[] args = WithDurationFilters(new[] { "-Action", actionName, "-Value", inputValue });
            ObservableCollection<SearchCandidate> candidates = new ObservableCollection<SearchCandidate>();
            bool previewCancelled = false;
            bool previewStopped = false;
            Window dialog = new Window
            {
                Title = "Select Videos to Add",
                Owner = this,
                Width = Math.Min(980, Math.Max(760, ActualWidth * 0.78)),
                Height = Math.Min(640, Math.Max(460, ActualHeight * 0.72)),
                MinWidth = 720,
                MinHeight = 420,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = Brush("#0B1020")
            };

            Grid root = new Grid { Margin = new Thickness(14) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = root;

            TextBlock heading = new TextBlock { Text = "Building filtered search list...", FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 0, 0, 10) };
            root.Children.Add(heading);
            int searchedCount = 0;
            int candidateTotal = 0;
            bool candidateCountNoticeShown = false;

            DataGrid grid = BuildSearchCandidateGrid(candidates);
            Grid.SetRow(grid, 1);
            root.Children.Add(grid);

            Grid footer = new Grid { Margin = new Thickness(0, 10, 0, 0) };
            footer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            footer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            footer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Grid.SetRow(footer, 2);
            root.Children.Add(footer);
            DockPanel buttonRow = new DockPanel { LastChildFill = false };
            footer.Children.Add(buttonRow);
            StackPanel leftButtons = new StackPanel { Orientation = Orientation.Horizontal };
            DockPanel.SetDock(leftButtons, Dock.Left);
            buttonRow.Children.Add(leftButtons);
            Button selectAll = Button("Select All", 100, 32);
            Button selectNone = Button("Deselect All", 110, 32);
            Button showConsole = Button("Show Console", 120, 32);
            selectAll.Margin = new Thickness(0, 0, 8, 0);
            selectNone.Margin = new Thickness(0, 0, 8, 0);
            showConsole.Margin = new Thickness(0, 0, 8, 0);
            leftButtons.Children.Add(selectAll);
            leftButtons.Children.Add(selectNone);
            leftButtons.Children.Add(showConsole);

            StackPanel rightButtons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            DockPanel.SetDock(rightButtons, Dock.Right);
            buttonRow.Children.Add(rightButtons);
            TextBlock buildingText = new TextBlock { Text = "Current search found 0 video(s). Reviewed 0 candidate(s).", Foreground = Brush("#CBD5E1"), FontSize = 13, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 8, 0, 0) };
            Grid.SetRow(buildingText, 1);
            footer.Children.Add(buildingText);
            TextBlock buildingHelpText = new TextBlock { Text = "Search is building the video list. You can stop the search at anytime and select videos from the current list.", Foreground = Brush("#94A3B8"), FontSize = 13, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 3, 0, 0) };
            Grid.SetRow(buildingHelpText, 2);
            footer.Children.Add(buildingHelpText);
            Button stopSearch = Button("Stop Search", 110, 32);
            Button ok = Button("OK", 90, 32);
            Button cancel = Button("Cancel", 90, 32);
            stopSearch.Margin = new Thickness(0, 0, 8, 0);
            ok.Margin = new Thickness(0, 0, 8, 0);
            cancel.Margin = new Thickness(0);
            stopSearch.Background = Brush("#7F1D1D");
            stopSearch.BorderBrush = Brush("#991B1B");
            ok.Background = Brush("#2563EB");
            ok.BorderBrush = Brush("#3B82F6");
            ok.Visibility = Visibility.Collapsed;
            rightButtons.Children.Add(stopSearch);
            rightButtons.Children.Add(ok);
            rightButtons.Children.Add(cancel);

            selectAll.Click += delegate
            {
                foreach (SearchCandidate item in candidates) { item.Selected = true; }
                grid.Items.Refresh();
            };
            selectNone.Click += delegate
            {
                foreach (SearchCandidate item in candidates) { item.Selected = false; }
                grid.Items.Refresh();
            };
            showConsole.Click += delegate { ShowConsoleWindow(); };
            ok.Click += delegate
            {
                grid.CommitEdit(DataGridEditingUnit.Cell, true);
                grid.CommitEdit(DataGridEditingUnit.Row, true);
                Keyboard.ClearFocus();
                dialog.DialogResult = true;
            };
            stopSearch.Click += delegate
            {
                previewStopped = true;
                stopSearch.IsEnabled = false;
                buildingText.Text = "Stopping search...";
                buildingHelpText.Text = "Current reviewed videos will remain available for selection.";
                SetOperation(operationName, "Stopping search", operationProgressBar == null ? 0 : operationProgressBar.Value);
                WriteOutput("Stopping search. Current candidates will remain available for selection...");
                KillActiveBackendProcessTree();
            };
            cancel.Click += delegate
            {
                previewCancelled = true;
                if (isRunning && (activeOperationAction == "SearchPreview" || activeOperationAction == "SourcePreview" || activeOperationAction == "VideoPreview")) { CancelOperation(); }
                dialog.DialogResult = false;
            };

            activeOperationAction = actionName;
            activeDownloadSnapshot.Clear();
            SetOperation(operationName, "Collecting candidates", 0);
            activeOperationCanCancel = true;
            MoveFocus(new TraversalRequest(FocusNavigationDirection.Next));
            SetBusy(true);
            if (cancelButton != null) { cancelButton.Visibility = Visibility.Collapsed; }
            WriteOutput(startMessage + " " + inputValue);
            activeStopwatch = Stopwatch.StartNew();

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.WorkingDirectory = assetsDir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.EnvironmentVariables["JUKEBOX_GUI_SESSION_STAMP"] = sessionStamp;
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + backendScript + "\" " + QuoteArgs(args);

            Process process = new Process();
            process.StartInfo = psi;
            process.EnableRaisingEvents = true;
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (TryAddSearchCandidate(e.Data, candidates, grid))
                    {
                        heading.Text = "Select videos to add to the list";
                        buildingText.Text = "Current search found " + candidates.Count.ToString() + " video(s). Reviewed " + searchedCount.ToString() + " candidate(s).";
                        return;
                    }
                    CaptureSearchStats(e.Data, ref searchedCount, ref candidateTotal);
                    int rawCandidateCount;
                    if (!candidateCountNoticeShown && TryGetRawCandidateCount(e.Data, out rawCandidateCount))
                    {
                        candidateCountNoticeShown = true;
                        string estimate = FormatEstimatedFilterTime(rawCandidateCount);
                        ShowAppInfo(
                            "Search found " + rawCandidateCount.ToString() + " possible video(s)." +
                            "\n\nFiltering the candidates may take approximately " + estimate + "." +
                            "\n\nYou can click Stop Search at any time to stop filtering and select from the videos reviewed so far.",
                            "Filtering Search Candidates",
                            dialog);
                    }
                    bool handledProgress = HandleProgressLine(e.Data);
                    if (handledProgress && buildingText.Visibility == Visibility.Visible)
                    {
                        int found = candidates.Count;
                        buildingText.Text = "Current search found " + found.ToString() + " video(s). Reviewed " + searchedCount.ToString() + " candidate(s).";
                    }
                    if (!handledProgress && !e.Data.StartsWith("PREVIEW_FILE|", StringComparison.OrdinalIgnoreCase)) { WriteOutput(e.Data); }
                }));
            };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) Dispatcher.BeginInvoke(new Action(delegate { WriteOutput(e.Data); }));
            };
            process.Exited += delegate
            {
                int exitCode = process.ExitCode;
                if (activeBackendProcess != null && activeBackendProcess.Id == process.Id) { activeBackendProcess = null; }
                process.Dispose();
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    TimeSpan elapsed = activeStopwatch == null ? TimeSpan.Zero : activeStopwatch.Elapsed;
                    activeStopwatch = null;
                    if (previewCancelled)
                    {
                        SetOperation(operationName, "Cancelled", 0);
                        WriteOutput(operationName + " preview cancelled in " + FormatElapsed(elapsed));
                        SetBusy(false);
                        buildingText.Visibility = Visibility.Collapsed;
                        buildingHelpText.Visibility = Visibility.Collapsed;
                        stopSearch.Visibility = Visibility.Collapsed;
                        return;
                    }
                    SetOperation(operationName, previewStopped ? "Stopped" : (exitCode == 0 ? "Choose videos" : "Finished with errors"), previewStopped ? operationProgressBar.Value : 100);
                    WriteOutput(previewStopped ? operationName + " stopped in " + FormatElapsed(elapsed) + ". Current candidates can be selected." : (exitCode == 0 ? operationName + " preview complete" : operationName + " preview failed") + " in " + FormatElapsed(elapsed));
                    SetBusy(false);
                    if (candidateTotal == 0) { candidateTotal = searchedCount; }
                    int remaining = candidates.Count;
                    int discarded = Math.Max(0, (previewStopped ? searchedCount : candidateTotal) - remaining);
                    if (dialog.IsVisible)
                    {
                        string stats = (previewStopped ? "Time elapsed: " : "Time to complete: ") + FormatElapsed(elapsed) +
                                       "\nSearched: " + (previewStopped ? searchedCount : candidateTotal).ToString() +
                                       "\nDiscarded: " + discarded.ToString() +
                                       "\nRemaining: " + remaining.ToString();
                        ShowAppInfo(stats, previewStopped ? "Search Stopped" : "Search Complete", dialog);
                    }
                    buildingText.Visibility = Visibility.Collapsed;
                    buildingHelpText.Visibility = Visibility.Collapsed;
                    stopSearch.Visibility = Visibility.Collapsed;
                    ok.Visibility = Visibility.Visible;
                    ok.IsEnabled = candidates.Count > 0;
                    heading.Text = candidates.Count == 0 ? "No matching videos were found." : "Select videos to add to the list";
                    if (exitCode != 0 && !previewStopped && dialog.IsVisible)
                    {
                        ShowAppInfo(operationName + " preview failed. Check the console log for details.", Title, dialog);
                    }
                }));
            };
            try
            {
                process.Start();
                activeBackendProcess = process;
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                WriteOutput(ex.Message);
                SetOperation(operationName, "Error", 100);
                activeBackendProcess = null;
                activeStopwatch = null;
                SetBusy(false);
                ShowAppInfo(ex.Message, Title);
            }

            bool? result = dialog.ShowDialog();
            if (result == true)
            {
                AddSelectedSearchCandidates(candidates);
            }
            else
            {
                WriteOutput(operationName + " selection cancelled. Video list was not changed.");
            }
        }

        private DataGrid BuildSearchCandidateGrid(System.Collections.IEnumerable candidates)
        {
            DataGrid grid = new DataGrid
            {
                AutoGenerateColumns = false,
                CanUserAddRows = false,
                CanUserDeleteRows = false,
                IsReadOnly = false,
                SelectionMode = DataGridSelectionMode.Extended,
                HeadersVisibility = DataGridHeadersVisibility.Column,
                GridLinesVisibility = DataGridGridLinesVisibility.Horizontal,
                Background = Brush("#0F172A"),
                Foreground = Brush("#E5E7EB"),
                RowBackground = Brush("#111827"),
                AlternatingRowBackground = Brush("#0F172A"),
                BorderBrush = Brush("#334155"),
                HorizontalGridLinesBrush = Brush("#263241"),
                VerticalGridLinesBrush = Brush("#263241"),
                ItemsSource = candidates,
                Margin = new Thickness(0, 0, 0, 12)
            };
            Style headerStyle = new Style(typeof(System.Windows.Controls.Primitives.DataGridColumnHeader));
            headerStyle.Setters.Add(new Setter(Control.BackgroundProperty, Brush("#1F2937")));
            headerStyle.Setters.Add(new Setter(Control.ForegroundProperty, Brush("#F8FAFC")));
            headerStyle.Setters.Add(new Setter(Control.FontWeightProperty, FontWeights.SemiBold));
            headerStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(8, 6, 8, 6)));
            headerStyle.Setters.Add(new Setter(Control.BorderBrushProperty, Brush("#334155")));
            headerStyle.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(0, 0, 1, 1)));
            grid.ColumnHeaderStyle = headerStyle;
            ApplyDarkScrollBars(grid);

            System.Windows.Data.Binding selectedBinding = new System.Windows.Data.Binding("Selected");
            selectedBinding.Mode = System.Windows.Data.BindingMode.TwoWay;
            selectedBinding.UpdateSourceTrigger = System.Windows.Data.UpdateSourceTrigger.PropertyChanged;
            grid.Columns.Add(new DataGridCheckBoxColumn { Header = "Add", Binding = selectedBinding, Width = 54 });
            grid.Columns.Add(new DataGridTextColumn { Header = "Artist", Binding = new System.Windows.Data.Binding("Artist"), Width = new DataGridLength(1.1, DataGridLengthUnitType.Star), IsReadOnly = true });
            grid.Columns.Add(new DataGridTextColumn { Header = "Title", Binding = new System.Windows.Data.Binding("Title"), Width = new DataGridLength(2.2, DataGridLengthUnitType.Star), IsReadOnly = true });
            grid.Columns.Add(new DataGridTextColumn { Header = "Video Length", Binding = new System.Windows.Data.Binding("Length"), Width = 105, IsReadOnly = true });
            return grid;
        }

        private bool TryAddSearchCandidate(string line, ObservableCollection<SearchCandidate> candidates, DataGrid grid)
        {
            if (String.IsNullOrWhiteSpace(line) || !line.StartsWith("CANDIDATE|", StringComparison.OrdinalIgnoreCase)) { return false; }
            string[] parts = line.Split('|');
            if (parts.Length < 5) { return true; }
            SearchCandidate candidate = new SearchCandidate
            {
                Selected = true,
                Url = DecodePreviewField(parts[1]),
                Artist = DecodePreviewField(parts[2]),
                Title = DecodePreviewField(parts[3]),
                Length = DecodePreviewField(parts[4])
            };
            candidates.Add(candidate);
            grid.ScrollIntoView(candidate);
            return true;
        }

        private void CaptureSearchStats(string line, ref int searchedCount, ref int candidateTotal)
        {
            if (String.IsNullOrWhiteSpace(line)) { return; }
            int rawCandidateCount;
            if (TryGetRawCandidateCount(line, out rawCandidateCount))
            {
                candidateTotal = Math.Max(candidateTotal, rawCandidateCount);
                return;
            }
            if (line.StartsWith("PROGRESS|Reviewing URLs|", StringComparison.OrdinalIgnoreCase))
            {
                string[] parts = line.Split('|');
                int current;
                int total;
                if (parts.Length >= 4 && Int32.TryParse(parts[2], out current) && Int32.TryParse(parts[3], out total))
                {
                    searchedCount = Math.Max(searchedCount, current);
                    candidateTotal = Math.Max(candidateTotal, total);
                }
                return;
            }

            System.Text.RegularExpressions.Match summary = System.Text.RegularExpressions.Regex.Match(line, @"^(\d+)\|(\d+)\|\d+\|\d+$");
            if (summary.Success)
            {
                int kept;
                int discarded;
                if (Int32.TryParse(summary.Groups[1].Value, out kept) && Int32.TryParse(summary.Groups[2].Value, out discarded))
                {
                    searchedCount = Math.Max(searchedCount, kept + discarded);
                    candidateTotal = Math.Max(candidateTotal, kept + discarded);
                }
            }
        }

        private string DecodePreviewField(string value)
        {
            try
            {
                return Encoding.UTF8.GetString(Convert.FromBase64String(value));
            }
            catch
            {
                return "";
            }
        }

        private void ShowSearchPreviewDialog(string previewFile)
        {
            List<SearchCandidate> candidates = LoadSearchCandidates(previewFile);
            if (candidates.Count == 0)
            {
                ShowAppInfo("No matching videos were found in the search window.", "Search Results");
                return;
            }

            Window dialog = new Window
            {
                Title = "Select Videos to Add",
                Owner = this,
                Topmost = true,
                Width = Math.Min(980, Math.Max(760, ActualWidth * 0.78)),
                Height = Math.Min(640, Math.Max(460, ActualHeight * 0.72)),
                MinWidth = 720,
                MinHeight = 420,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = Brush("#0B1020")
            };

            Grid root = new Grid { Margin = new Thickness(14) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            dialog.Content = root;

            TextBlock heading = new TextBlock { Text = "Select videos to add to the list", FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 0, 0, 10) };
            root.Children.Add(heading);

            DataGrid grid = new DataGrid
            {
                AutoGenerateColumns = false,
                CanUserAddRows = false,
                CanUserDeleteRows = false,
                IsReadOnly = false,
                SelectionMode = DataGridSelectionMode.Extended,
                HeadersVisibility = DataGridHeadersVisibility.Column,
                GridLinesVisibility = DataGridGridLinesVisibility.Horizontal,
                Background = Brush("#0F172A"),
                Foreground = Brush("#E5E7EB"),
                RowBackground = Brush("#111827"),
                AlternatingRowBackground = Brush("#0F172A"),
                BorderBrush = Brush("#334155"),
                HorizontalGridLinesBrush = Brush("#263241"),
                VerticalGridLinesBrush = Brush("#263241"),
                ItemsSource = candidates,
                Margin = new Thickness(0, 0, 0, 12)
            };
            grid.Columns.Add(new DataGridCheckBoxColumn { Header = "Add", Binding = new System.Windows.Data.Binding("Selected"), Width = 54 });
            grid.Columns.Add(new DataGridTextColumn { Header = "Artist", Binding = new System.Windows.Data.Binding("Artist"), Width = new DataGridLength(1.1, DataGridLengthUnitType.Star), IsReadOnly = true });
            grid.Columns.Add(new DataGridTextColumn { Header = "Title", Binding = new System.Windows.Data.Binding("Title"), Width = new DataGridLength(2.2, DataGridLengthUnitType.Star), IsReadOnly = true });
            grid.Columns.Add(new DataGridTextColumn { Header = "Video Length", Binding = new System.Windows.Data.Binding("Length"), Width = 105, IsReadOnly = true });
            Grid.SetRow(grid, 1);
            root.Children.Add(grid);

            DockPanel footer = new DockPanel { LastChildFill = false };
            Grid.SetRow(footer, 2);
            root.Children.Add(footer);
            StackPanel leftButtons = new StackPanel { Orientation = Orientation.Horizontal };
            DockPanel.SetDock(leftButtons, Dock.Left);
            footer.Children.Add(leftButtons);
            Button selectAll = Button("Select All", 100, 32);
            Button selectNone = Button("Deselect All", 110, 32);
            selectAll.Margin = new Thickness(0, 0, 8, 0);
            selectNone.Margin = new Thickness(0, 0, 8, 0);
            leftButtons.Children.Add(selectAll);
            leftButtons.Children.Add(selectNone);

            StackPanel rightButtons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            DockPanel.SetDock(rightButtons, Dock.Right);
            footer.Children.Add(rightButtons);
            Button ok = Button("OK", 90, 32);
            Button cancel = Button("Cancel", 90, 32);
            ok.Margin = new Thickness(0, 0, 8, 0);
            cancel.Margin = new Thickness(0);
            ok.Background = Brush("#2563EB");
            ok.BorderBrush = Brush("#3B82F6");
            rightButtons.Children.Add(ok);
            rightButtons.Children.Add(cancel);

            selectAll.Click += delegate
            {
                foreach (SearchCandidate item in candidates) { item.Selected = true; }
                grid.Items.Refresh();
            };
            selectNone.Click += delegate
            {
                foreach (SearchCandidate item in candidates) { item.Selected = false; }
                grid.Items.Refresh();
            };
            ok.Click += delegate { dialog.DialogResult = true; };
            cancel.Click += delegate { dialog.DialogResult = false; };

            bool? result = dialog.ShowDialog();
            if (result == true)
            {
                AddSelectedSearchCandidates(candidates);
            }
            else
            {
                WriteOutput("Search selection cancelled. Video list was not changed.");
            }
        }

        private List<SearchCandidate> LoadSearchCandidates(string previewFile)
        {
            List<SearchCandidate> candidates = new List<SearchCandidate>();
            if (!File.Exists(previewFile)) { return candidates; }
            string[] lines = File.ReadAllLines(previewFile, Encoding.UTF8);
            for (int i = 1; i < lines.Length; i++)
            {
                string[] parts = lines[i].Split('\t');
                if (parts.Length < 4 || String.IsNullOrWhiteSpace(parts[0])) { continue; }
                candidates.Add(new SearchCandidate
                {
                    Selected = true,
                    Url = parts[0].Trim(),
                    Artist = parts[1].Trim(),
                    Title = parts[2].Trim(),
                    Length = parts[3].Trim()
                });
            }
            return candidates;
        }

        private void AddSelectedSearchCandidates(IEnumerable<SearchCandidate> candidates)
        {
            List<string> selected = new List<string>();
            bool labelsChanged = false;
            HashSet<string> existingIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (File.Exists(urlFile))
            {
                foreach (string line in File.ReadAllLines(urlFile))
                {
                    string id = GetYouTubeId(line);
                    if (id.Length > 0) { existingIds.Add(id); }
                }
            }

            foreach (SearchCandidate candidate in candidates)
            {
                if (!candidate.Selected) { continue; }
                string id = GetYouTubeId(candidate.Url);
                if (id.Length == 0) { continue; }
                string label = BuildCandidateDisplayLabel(candidate);
                if (!String.IsNullOrWhiteSpace(label) && !label.StartsWith("Title unavailable", StringComparison.OrdinalIgnoreCase))
                {
                    urlDisplayLabels[id] = label;
                    labelsChanged = true;
                }
                if (existingIds.Contains(id)) { continue; }
                selected.Add("https://youtu.be/" + id);
                existingIds.Add(id);
            }
            if (labelsChanged) { SaveVideoDisplayLabels(); }

            if (selected.Count == 0)
            {
                ShowAppInfo("No selected videos were added.", "Search Results");
                return;
            }

            Directory.CreateDirectory(resourcesDir);
            if (!File.Exists(urlFile)) { File.WriteAllText(urlFile, "", Encoding.ASCII); }
            File.AppendAllLines(urlFile, selected, Encoding.ASCII);
            SortUrlFileByDisplayLabel();
            RefreshUrls();
            WriteOutput("Added " + selected.Count.ToString() + " selected video(s).");
            SetOperation("Search", "Added " + selected.Count.ToString() + " selected video(s)", 100);
            ShowAppInfo(selected.Count.ToString() + " video(s) were added to the list.", "Videos Added");
        }

        private void KillActiveBackendProcessTree()
        {
            try
            {
                if (activeBackendProcess == null || activeBackendProcess.HasExited) { return; }
                KillProcessTree(activeBackendProcess.Id);
            }
            catch
            {
            }
        }

        private void CancelOperation()
        {
            if (!isRunning) { return; }
            if (!activeOperationCanCancel)
            {
                WriteOutput("Cancel is disabled for this operation.");
                return;
            }
            SetOperation(currentOperationText.Text, "Cancelling", operationProgressBar == null ? 0 : operationProgressBar.Value);
            WriteOutput("Cancelling current operation...");
            KillActiveBackendProcessTree();
            RunCancelRollback();
            if (activeOperationAction == "Download")
            {
                RestoreGuiDownloadSnapshot();
                if (lastDownloadRollbackMoveCount > 0)
                {
                    ShowAppInfo("Cancelled download. New or partial download files were moved to:\n\n" + Path.Combine(downloadsDir, "discard"), "Download Cancelled");
                }
                else
                {
                    ShowAppInfo("Cancelled download. No new download files were found to move.", "Download Cancelled");
                }
            }
            else if (activeOperationAction == "Search" || activeOperationAction == "SearchPreview" || activeOperationAction == "SourcePreview" || activeOperationAction == "VideoPreview")
            {
                ShowAppInfo("Cancelled import/search. The video list was left unchanged or restored to its original state.", "Cancelled");
            }
            RefreshUrls();
        }

        private void CaptureDownloadSnapshot()
        {
            activeDownloadSnapshot.Clear();
            activeDownloadSnapshotCaptured = false;
            lastDownloadRollbackMoveCount = 0;
            try
            {
                activeDownloadSnapshotCaptured = true;
                if (!Directory.Exists(downloadsDir)) { return; }
                string discardDir = Path.Combine(downloadsDir, "discard");
                foreach (string file in Directory.GetFiles(downloadsDir, "*", SearchOption.AllDirectories))
                {
                    if (IsPathInsideFolder(file, discardDir)) { continue; }
                    activeDownloadSnapshot.Add(Path.GetFullPath(file));
                }
            }
            catch (Exception ex)
            {
                WriteOutput("Download rollback snapshot warning: " + ex.Message);
            }
        }

        private void RestoreGuiDownloadSnapshot()
        {
            if (!activeDownloadSnapshotCaptured) { return; }
            try
            {
                lastDownloadRollbackMoveCount = 0;
                if (!Directory.Exists(downloadsDir)) { return; }
                string discardDir = Path.Combine(downloadsDir, "discard");
                Directory.CreateDirectory(discardDir);
                int moved = 0;
                foreach (string file in Directory.GetFiles(downloadsDir, "*", SearchOption.AllDirectories))
                {
                    string fullPath = Path.GetFullPath(file);
                    if (IsPathInsideFolder(fullPath, discardDir)) { continue; }
                    if (activeDownloadSnapshot.Contains(fullPath)) { continue; }
                    string destination = GetUniqueFilePath(discardDir, Path.GetFileName(fullPath));
                    File.Move(fullPath, destination);
                    moved++;
                }
                if (moved > 0)
                {
                    WriteOutput("Cancelled download. New/partial files were moved to downloads\\discard: " + moved);
                }
                else
                {
                    WriteOutput("Cancelled download. No new/partial download files were found to move.");
                }
                lastDownloadRollbackMoveCount = moved;
                activeDownloadSnapshot.Clear();
                activeDownloadSnapshotCaptured = false;
            }
            catch (Exception ex)
            {
                WriteOutput("Download rollback warning: " + ex.Message);
            }
        }

        private void MigrateHiddenLogsFolder()
        {
            try
            {
                string oldLogsDir = Path.Combine(dataRoot, "logs");
                if (!Directory.Exists(oldLogsDir)) { return; }

                Directory.CreateDirectory(logsDir);
                foreach (string oldPath in Directory.GetFiles(oldLogsDir, "*", SearchOption.AllDirectories))
                {
                    string relativePath = oldPath.Substring(oldLogsDir.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                    string newPath = Path.Combine(logsDir, relativePath);
                    string newParent = Path.GetDirectoryName(newPath);
                    if (!String.IsNullOrWhiteSpace(newParent)) { Directory.CreateDirectory(newParent); }
                    if (File.Exists(newPath)) { newPath = GetUniqueFilePath(newParent, Path.GetFileName(newPath)); }
                    File.Move(oldPath, newPath);
                }

                if (Directory.GetFiles(oldLogsDir, "*", SearchOption.AllDirectories).Length == 0)
                {
                    Directory.Delete(oldLogsDir, true);
                }
            }
            catch
            {
            }
        }

        private bool TryGetRawCandidateCount(string line, out int count)
        {
            count = 0;
            if (String.IsNullOrWhiteSpace(line)) { return false; }
            System.Text.RegularExpressions.Match match = System.Text.RegularExpressions.Regex.Match(line, @"^Found\s+(\d+)\s+candidate URL\(s\)\.$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            return match.Success && Int32.TryParse(match.Groups[1].Value, out count);
        }

        private string FormatEstimatedFilterTime(int candidateCount)
        {
            TimeSpan estimate = TimeSpan.FromSeconds(Math.Max(1, candidateCount) * 7);
            if (estimate.TotalMinutes < 1) { return "less than 1 minute"; }
            return Math.Ceiling(estimate.TotalMinutes).ToString() + " minute(s)";
        }

        private string GetUniqueFilePath(string folder, string fileName)
        {
            string candidate = Path.Combine(folder, fileName);
            if (!File.Exists(candidate)) { return candidate; }

            string name = Path.GetFileNameWithoutExtension(fileName);
            string extension = Path.GetExtension(fileName);
            int index = 1;
            do
            {
                candidate = Path.Combine(folder, name + " (" + index.ToString() + ")" + extension);
                index++;
            } while (File.Exists(candidate));
            return candidate;
        }

        private long GetTotalFileBytes(IEnumerable<string> files)
        {
            long total = 0;
            foreach (string file in files)
            {
                try
                {
                    if (File.Exists(file)) { total += new FileInfo(file).Length; }
                }
                catch
                {
                }
            }
            return total;
        }

        private bool HasEnoughSpaceForMove(string target, long fileBytes)
        {
            try
            {
                DriveInfo drive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(target)));
                return drive.AvailableFreeSpace >= fileBytes + SsdMoveReserveBytes;
            }
            catch
            {
                return false;
            }
        }

        private void ShowAppInfo(string message, string title)
        {
            ShowAppDialog(message, title, MessageBoxButton.OK);
        }

        private void ShowAppInfo(string message, string title, Window owner)
        {
            ShowAppDialog(message, title, MessageBoxButton.OK, owner);
        }

        private MessageBoxResult ShowAppDialog(string message, string title, MessageBoxButton buttons)
        {
            return ShowAppDialog(message, title, buttons, this);
        }

        private MessageBoxResult ShowAppDialog(string message, string title, MessageBoxButton buttons, Window owner)
        {
            if (!Dispatcher.CheckAccess())
            {
                return (MessageBoxResult)Dispatcher.Invoke(new Func<MessageBoxResult>(delegate
                {
                    return ShowAppDialog(message, title, buttons, owner);
                }));
            }

            if (owner == null) { owner = this; }

            Window dialog = new Window
            {
                Title = title,
                Owner = owner,
                Width = 430,
                SizeToContent = SizeToContent.Height,
                ResizeMode = ResizeMode.NoResize,
                WindowStartupLocation = WindowStartupLocation.Manual,
                Background = Brush("#0B1020"),
                ShowInTaskbar = false
            };
            MessageBoxResult result = MessageBoxResult.None;

            Grid root = new Grid { Margin = new Thickness(18) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            dialog.Content = root;

            TextBlock icon = new TextBlock { Text = "i", Width = 28, Height = 28, FontSize = 18, FontWeight = FontWeights.Bold, TextAlignment = TextAlignment.Center, Foreground = Brush("#FFFFFF"), Background = Brush("#2563EB"), Margin = new Thickness(0, 0, 14, 0), VerticalAlignment = VerticalAlignment.Top };
            root.Children.Add(icon);

            TextBlock body = new TextBlock { Text = message, Foreground = Brush("#E5E7EB"), TextWrapping = TextWrapping.Wrap, FontSize = 12, Margin = new Thickness(0, 2, 0, 18) };
            Grid.SetColumn(body, 1);
            root.Children.Add(body);

            StackPanel buttonPanel = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            Grid.SetRow(buttonPanel, 1);
            Grid.SetColumn(buttonPanel, 1);
            root.Children.Add(buttonPanel);

            if (buttons == MessageBoxButton.YesNo || buttons == MessageBoxButton.YesNoCancel)
            {
                buttonPanel.Children.Add(AppDialogButton("Yes", true, delegate { result = MessageBoxResult.Yes; dialog.DialogResult = true; }));
                buttonPanel.Children.Add(AppDialogButton("No", false, delegate { result = MessageBoxResult.No; dialog.DialogResult = true; }));
                if (buttons == MessageBoxButton.YesNoCancel)
                {
                    buttonPanel.Children.Add(AppDialogButton("Cancel", false, delegate { result = MessageBoxResult.Cancel; dialog.DialogResult = true; }));
                }
            }
            else
            {
                buttonPanel.Children.Add(AppDialogButton("OK", true, delegate { result = MessageBoxResult.OK; dialog.DialogResult = true; }));
            }

            dialog.SourceInitialized += delegate
            {
                double ownerWidth = owner.ActualWidth > 0 ? owner.ActualWidth : owner.Width;
                double ownerHeight = owner.ActualHeight > 0 ? owner.ActualHeight : owner.Height;
                dialog.Left = owner.Left + Math.Max(0, (ownerWidth - dialog.ActualWidth) / 2);
                dialog.Top = owner.Top + Math.Max(0, (ownerHeight - dialog.ActualHeight) / 2);
            };
            dialog.ShowDialog();
            return result;
        }

        private Button AppDialogButton(string text, bool isDefault, RoutedEventHandler clickHandler)
        {
            Button button = new Button { Content = text, Width = 76, Height = 28, Margin = new Thickness(8, 0, 0, 0), IsDefault = isDefault, Background = Brush(isDefault ? "#2563EB" : "#1F2937"), Foreground = Brush("#F8FAFC"), BorderBrush = Brush(isDefault ? "#3B82F6" : "#374151"), BorderThickness = new Thickness(1), Cursor = Cursors.Hand };
            ApplyButtonTemplate(button, 0);
            button.Click += clickHandler;
            return button;
        }

        private string FormatBytes(long bytes)
        {
            if (bytes >= 1024L * 1024L * 1024L) { return ((double)bytes / (1024L * 1024L * 1024L)).ToString("N2") + " GB"; }
            if (bytes >= 1024L * 1024L) { return ((double)bytes / (1024L * 1024L)).ToString("N2") + " MB"; }
            if (bytes >= 1024L) { return ((double)bytes / 1024L).ToString("N2") + " KB"; }
            return bytes.ToString() + " bytes";
        }

        private string GetFileReviewKey(string fileName)
        {
            string baseName = Path.GetFileNameWithoutExtension(fileName);
            string extension = Path.GetExtension(fileName).ToLowerInvariant();
            string key = baseName;
            int dash = baseName.IndexOf(" - ", StringComparison.Ordinal);
            if (dash >= 0)
            {
                string artist = baseName.Substring(0, dash);
                string title = baseName.Substring(dash + 3);
                int open = title.IndexOf('(');
                int close = title.IndexOf(')');
                if (open >= 0 && close > open)
                {
                    title = (title.Substring(0, open) + " " + title.Substring(open + 1, close - open - 1)).Trim();
                }
                else if (open >= 0)
                {
                    title = title.Substring(0, open).Trim();
                }
                title = System.Text.RegularExpressions.Regex.Replace(title, @"\b(feat|ft|featuring)\.?\s+.*$", " ", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                key = artist + " " + title;
            }
            key = key.Normalize(NormalizationForm.FormD);
            StringBuilder clean = new StringBuilder();
            foreach (char ch in key)
            {
                System.Globalization.UnicodeCategory category = System.Globalization.CharUnicodeInfo.GetUnicodeCategory(ch);
                if (category == System.Globalization.UnicodeCategory.NonSpacingMark) { continue; }
                clean.Append(ch);
            }
            key = clean.ToString().ToLowerInvariant();
            key = System.Text.RegularExpressions.Regex.Replace(key, "_+", " ");
            key = System.Text.RegularExpressions.Regex.Replace(key, @"[^a-z0-9]+", " ");
            key = System.Text.RegularExpressions.Regex.Replace(key, @"\s+", " ").Trim();
            if (key.Length == 0) { key = baseName.ToLowerInvariant().Trim(); }
            return extension + "|" + key;
        }

        private void RunCancelRollback()
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.WorkingDirectory = assetsDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.EnvironmentVariables["JUKEBOX_GUI_SESSION_STAMP"] = sessionStamp;
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + backendScript + "\" \"-Action\" \"RollbackCancel\"";

                Process rollback = Process.Start(psi);
                if (rollback == null) { return; }
                string output = rollback.StandardOutput.ReadToEnd();
                string error = rollback.StandardError.ReadToEnd();
                rollback.WaitForExit(10000);
                foreach (string line in output.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries))
                {
                    WriteOutput(line);
                }
                foreach (string line in error.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries))
                {
                    WriteOutput(line);
                }
            }
            catch (Exception ex)
            {
                WriteOutput("Rollback check failed: " + ex.Message);
            }
        }

        private void RotateArchiveLogs()
        {
            try
            {
                Directory.CreateDirectory(archiveLogDir);
                ArchiveCurrentLogs("CONSOLE_LOG", "gui_console_*.log", "CONSOLE_LOG");
                ArchiveCurrentLogs("URL_BUILDER_LOG", "jukebox_gui_urls_*.log", "URL_BUILDER_LOG");
                ArchiveCurrentLogs("JUKEBOX_WIZARD_LOG", "jukebox_gui_download_*.log", "JUKEBOX_WIZARD_LOG");
            }
            catch
            {
            }
        }

        private void ArchiveCurrentLogs(string folderName, string pattern, string currentFolderName)
        {
            string targetDir = Path.Combine(archiveLogDir, folderName);
            Directory.CreateDirectory(targetDir);
            MoveLogsIntoArchive(logsDir, targetDir, pattern);
            MoveLogsIntoArchive(Path.Combine(logsDir, currentFolderName), targetDir, pattern);
            RotateLogFolder(targetDir, pattern, 5);
        }

        private void MoveLogsIntoArchive(string sourceDir, string targetDir, string pattern)
        {
            if (!Directory.Exists(sourceDir)) { return; }
            if (String.Equals(Path.GetFullPath(sourceDir).TrimEnd(Path.DirectorySeparatorChar), Path.GetFullPath(targetDir).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)) { return; }
            foreach (string oldLog in Directory.GetFiles(sourceDir, pattern, SearchOption.TopDirectoryOnly))
            {
                try
                {
                    string destination = Path.Combine(targetDir, Path.GetFileName(oldLog));
                    if (!File.Exists(destination))
                    {
                        File.Move(oldLog, destination);
                    }
                }
                catch
                {
                }
            }
        }

        private void RotateLogFolder(string folder, string pattern, int keep)
        {
            List<FileInfo> logs = new List<FileInfo>();
            foreach (string log in Directory.GetFiles(folder, pattern, SearchOption.TopDirectoryOnly))
            {
                logs.Add(new FileInfo(log));
            }
            logs.Sort(delegate(FileInfo left, FileInfo right)
            {
                return right.LastWriteTimeUtc.CompareTo(left.LastWriteTimeUtc);
            });
            for (int i = keep; i < logs.Count; i++)
            {
                try { logs[i].Delete(); } catch { }
            }
        }

        private void KillProcessTree(int processId)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "taskkill.exe";
                psi.Arguments = "/PID " + processId + " /T /F";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                Process killer = Process.Start(psi);
                if (killer != null) { killer.WaitForExit(3000); }
            }
            catch
            {
            }
        }

        private void RefreshUrls()
        {
            urlList.Items.Clear();
            List<UrlDisplayItem> items = new List<UrlDisplayItem>();
            if (File.Exists(urlFile))
            {
                foreach (string line in File.ReadAllLines(urlFile))
                {
                    string trimmed = line.Trim();
                    if (trimmed.Length > 0)
                    {
                        items.Add(new UrlDisplayItem { Url = trimmed, Display = GetUrlDisplayLabel(trimmed) });
                    }
                }
            }
            items.Sort(delegate(UrlDisplayItem left, UrlDisplayItem right)
            {
                return StringComparer.OrdinalIgnoreCase.Compare(left.Display, right.Display);
            });
            foreach (UrlDisplayItem item in items)
            {
                urlList.Items.Add(item);
            }
            urlCountText.Text = "# of Vids: " + urlList.Items.Count;
            if (!isRunning) SetOperation("Idle", "Ready", 0);
        }

        private void SortUrlFileByDisplayLabel()
        {
            if (!File.Exists(urlFile)) { return; }

            List<UrlDisplayItem> items = new List<UrlDisplayItem>();
            HashSet<string> seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string line in File.ReadAllLines(urlFile))
            {
                string trimmed = line.Trim();
                if (trimmed.Length == 0) { continue; }
                string id = GetYouTubeId(trimmed);
                if (id.Length > 0)
                {
                    if (seenIds.Contains(id)) { continue; }
                    seenIds.Add(id);
                }
                items.Add(new UrlDisplayItem { Url = trimmed, Display = GetUrlDisplayLabel(trimmed) });
            }

            items.Sort(delegate(UrlDisplayItem left, UrlDisplayItem right)
            {
                return StringComparer.OrdinalIgnoreCase.Compare(left.Display, right.Display);
            });

            List<string> sortedUrls = new List<string>();
            foreach (UrlDisplayItem item in items)
            {
                sortedUrls.Add(item.Url);
            }
            File.WriteAllLines(urlFile, sortedUrls.ToArray(), Encoding.ASCII);
        }

        private void ApplyDarkScrollBars(Control control)
        {
            string xaml =
@"<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
         xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
         TargetType='{x:Type ScrollBar}'>
    <Setter Property='Background' Value='#0B1020'/>
    <Setter Property='Foreground' Value='#CBD5E1'/>
    <Style.Resources>
        <Style TargetType='{x:Type RepeatButton}'>
            <Setter Property='Foreground' Value='#CBD5E1'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='{x:Type RepeatButton}'>
                        <Border x:Name='RepeatButtonChrome'
                                Background='{TemplateBinding Background}'
                                BorderBrush='{TemplateBinding BorderBrush}'
                                BorderThickness='{TemplateBinding BorderThickness}'
                                SnapsToDevicePixels='True'>
                            <ContentPresenter x:Name='RepeatButtonContent'
                                              HorizontalAlignment='Center'
                                              VerticalAlignment='Center'
                                              RecognizesAccessKey='True'
                                              TextElement.Foreground='{TemplateBinding Foreground}'/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property='IsMouseOver' Value='True'>
                                <Setter TargetName='RepeatButtonChrome' Property='Background' Value='#CBD5E1'/>
                                <Setter TargetName='RepeatButtonChrome' Property='BorderBrush' Value='#E2E8F0'/>
                                <Setter TargetName='RepeatButtonContent' Property='TextElement.Foreground' Value='#0F172A'/>
                            </Trigger>
                            <Trigger Property='IsPressed' Value='True'>
                                <Setter TargetName='RepeatButtonChrome' Property='Background' Value='#94A3B8'/>
                                <Setter TargetName='RepeatButtonChrome' Property='BorderBrush' Value='#CBD5E1'/>
                                <Setter TargetName='RepeatButtonContent' Property='TextElement.Foreground' Value='#0B1020'/>
                            </Trigger>
                            <Trigger Property='IsEnabled' Value='False'>
                                <Setter TargetName='RepeatButtonChrome' Property='Opacity' Value='0.55'/>
                                <Setter TargetName='RepeatButtonContent' Property='TextElement.Foreground' Value='#94A3B8'/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Style.Resources>
    <Style.Triggers>
        <Trigger Property='Orientation' Value='Horizontal'>
            <Setter Property='Height' Value='16'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='{x:Type ScrollBar}'>
                        <Grid Height='16' Background='#0B1020' SnapsToDevicePixels='True'>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width='16'/>
                                <ColumnDefinition Width='*'/>
                                <ColumnDefinition Width='16'/>
                            </Grid.ColumnDefinitions>
                            <RepeatButton Grid.Column='0' Command='ScrollBar.LineLeftCommand' Content='&#x25C0;' Background='#0B1020' Foreground='#CBD5E1' BorderBrush='#1E293B' BorderThickness='1' Padding='0'/>
                            <Border Grid.Column='1' Background='#111827' BorderBrush='#1E293B' BorderThickness='0,1,0,1'>
                                <Track x:Name='PART_Track' IsDirectionReversed='False' Margin='4,0'>
                                    <Track.DecreaseRepeatButton>
                                        <RepeatButton Command='ScrollBar.PageLeftCommand' Background='#111827' BorderThickness='0'/>
                                    </Track.DecreaseRepeatButton>
                                    <Track.Thumb>
                                        <Thumb Height='6' Background='#64748B' BorderBrush='#94A3B8' BorderThickness='0'/>
                                    </Track.Thumb>
                                    <Track.IncreaseRepeatButton>
                                        <RepeatButton Command='ScrollBar.PageRightCommand' Background='#111827' BorderThickness='0'/>
                                    </Track.IncreaseRepeatButton>
                                </Track>
                            </Border>
                            <RepeatButton Grid.Column='2' Command='ScrollBar.LineRightCommand' Content='&#x25B6;' Background='#0B1020' Foreground='#CBD5E1' BorderBrush='#1E293B' BorderThickness='1' Padding='0'/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Trigger>
        <Trigger Property='Orientation' Value='Vertical'>
            <Setter Property='Width' Value='16'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='{x:Type ScrollBar}'>
                        <Grid Width='16' Background='#0B1020' SnapsToDevicePixels='True'>
                            <Grid.RowDefinitions>
                                <RowDefinition Height='16'/>
                                <RowDefinition Height='*'/>
                                <RowDefinition Height='16'/>
                            </Grid.RowDefinitions>
                            <RepeatButton Grid.Row='0' Command='ScrollBar.LineUpCommand' Content='&#x25B2;' Background='#0B1020' Foreground='#CBD5E1' BorderBrush='#1E293B' BorderThickness='1' Padding='0'/>
                            <Border Grid.Row='1' Background='#111827' BorderBrush='#1E293B' BorderThickness='1,0,1,0'>
                                <Track x:Name='PART_Track' IsDirectionReversed='True' Margin='0,4'>
                                    <Track.DecreaseRepeatButton>
                                        <RepeatButton Command='ScrollBar.PageUpCommand' Background='#111827' BorderThickness='0'/>
                                    </Track.DecreaseRepeatButton>
                                    <Track.Thumb>
                                        <Thumb Width='6' Background='#64748B' BorderBrush='#94A3B8' BorderThickness='0'/>
                                    </Track.Thumb>
                                    <Track.IncreaseRepeatButton>
                                        <RepeatButton Command='ScrollBar.PageDownCommand' Background='#111827' BorderThickness='0'/>
                                    </Track.IncreaseRepeatButton>
                                </Track>
                            </Border>
                            <RepeatButton Grid.Row='2' Command='ScrollBar.LineDownCommand' Content='&#x25BC;' Background='#0B1020' Foreground='#CBD5E1' BorderBrush='#1E293B' BorderThickness='1' Padding='0'/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Trigger>
    </Style.Triggers>
</Style>";

            control.Resources[typeof(System.Windows.Controls.Primitives.ScrollBar)] = System.Windows.Markup.XamlReader.Parse(xaml);
            control.Resources[SystemColors.ScrollBarBrushKey] = Brush("#0B1020");
            control.Resources[SystemColors.ControlBrushKey] = Brush("#111827");
            control.Resources[SystemColors.ControlDarkBrushKey] = Brush("#0B1020");
            control.Resources[SystemColors.ControlDarkDarkBrushKey] = Brush("#020617");
            control.Resources[SystemColors.ControlLightBrushKey] = Brush("#475569");
            control.Resources[SystemColors.ControlLightLightBrushKey] = Brush("#64748B");
            control.Resources[SystemColors.HighlightBrushKey] = Brush("#2563EB");
        }

        private string GetUrlDisplayLabel(string url)
        {
            string id = GetYouTubeId(url);
            if (id.Length == 0) { return "Unrecognized video entry"; }

            LoadVideoDisplayLabels();
            string displayLabel;
            if (urlDisplayLabels.TryGetValue(id, out displayLabel) && !String.IsNullOrWhiteSpace(displayLabel))
            {
                return displayLabel;
            }

            string title = GetCachedVideoTitle(id);
            if (String.IsNullOrWhiteSpace(title)) { return "Title unavailable (" + id + ")"; }

            title = title.Trim();
            int dash = title.IndexOf(" - ", StringComparison.Ordinal);
            if (dash > 0 && dash + 3 < title.Length)
            {
                string artist = title.Substring(0, dash).Trim();
                string song = title.Substring(dash + 3).Trim();
                if (artist.Length > 0 && song.Length > 0) { return artist + " - " + song; }
            }
            return title;
        }

        private string BuildCandidateDisplayLabel(SearchCandidate candidate)
        {
            string artist = candidate == null ? "" : (candidate.Artist ?? "").Trim();
            string title = candidate == null ? "" : (candidate.Title ?? "").Trim();
            if (artist.Length > 0 && title.Length > 0) { return artist + " - " + title; }
            if (title.Length > 0) { return title; }
            if (artist.Length > 0) { return artist; }
            string id = candidate == null ? "" : GetYouTubeId(candidate.Url);
            return id.Length > 0 ? "Title unavailable (" + id + ")" : "Title unavailable";
        }

        private string GetVideoDisplayLabelCacheFile()
        {
            return Path.Combine(resourceCacheDir, "jukebox_video_display_labels.tsv");
        }

        private void LoadVideoDisplayLabels()
        {
            try
            {
                string path = GetVideoDisplayLabelCacheFile();
                if (!File.Exists(path)) { return; }
                foreach (string line in File.ReadAllLines(path, Encoding.UTF8))
                {
                    string[] parts = line.Split(new[] { '\t' }, 2);
                    if (parts.Length == 2 && parts[0].Trim().Length > 0 && parts[1].Trim().Length > 0)
                    {
                        urlDisplayLabels[parts[0].Trim()] = parts[1].Trim();
                    }
                }
            }
            catch
            {
            }
        }

        private void SaveVideoDisplayLabels()
        {
            try
            {
                Directory.CreateDirectory(resourceCacheDir);
                List<string> lines = new List<string>();
                foreach (KeyValuePair<string, string> pair in urlDisplayLabels)
                {
                    if (!String.IsNullOrWhiteSpace(pair.Key) && !String.IsNullOrWhiteSpace(pair.Value))
                    {
                        lines.Add(pair.Key + "\t" + pair.Value.Replace("\t", " "));
                    }
                }
                lines.Sort(StringComparer.OrdinalIgnoreCase);
                File.WriteAllLines(GetVideoDisplayLabelCacheFile(), lines.ToArray(), Encoding.UTF8);
            }
            catch
            {
            }
        }

        private string GetCachedVideoTitle(string id)
        {
            try
            {
                string cacheFile = Path.Combine(resourceCacheDir, "jukebox_url_metadata_cache.json");
                if (!File.Exists(cacheFile)) { return ""; }
                string json = File.ReadAllText(cacheFile, Encoding.UTF8);
                string itemPattern = "\"" + System.Text.RegularExpressions.Regex.Escape(id) + "\"\\s*:\\s*\\{(?<body>.*?)\\n\\s*\\}";
                System.Text.RegularExpressions.Match item = System.Text.RegularExpressions.Regex.Match(json, itemPattern, System.Text.RegularExpressions.RegexOptions.Singleline);
                if (!item.Success) { return ""; }
                System.Text.RegularExpressions.Match title = System.Text.RegularExpressions.Regex.Match(item.Groups["body"].Value, "\"title\"\\s*:\\s*\"(?<title>(?:\\\\.|[^\"])*)\"", System.Text.RegularExpressions.RegexOptions.Singleline);
                if (!title.Success) { return ""; }
                return DecodeJsonString(title.Groups["title"].Value);
            }
            catch
            {
                return "";
            }
        }

        private string DecodeJsonString(string value)
        {
            if (String.IsNullOrEmpty(value)) { return ""; }
            value = value.Replace("\\\"", "\"").Replace("\\\\", "\\").Replace("\\/", "/").Replace("\\n", " ").Replace("\\r", " ").Replace("\\t", " ");
            return System.Text.RegularExpressions.Regex.Replace(value, @"\\u([0-9a-fA-F]{4})", delegate(System.Text.RegularExpressions.Match match)
            {
                int code;
                if (Int32.TryParse(match.Groups[1].Value, System.Globalization.NumberStyles.HexNumber, null, out code))
                {
                    return ((char)code).ToString();
                }
                return match.Value;
            });
        }

        private Grid BuildOperationStatusRow()
        {
            Grid grid = new Grid { Margin = new Thickness(2, 8, 0, 0) };
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            grid.Children.Add(new TextBlock { Text = "Current operation", FontSize = 11, Foreground = Brush("#64748B"), VerticalAlignment = VerticalAlignment.Center });
            currentOperationText = new TextBlock { Text = "Idle", FontSize = 12, Foreground = Brush("#CBD5E1"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 36, 0), TextTrimming = TextTrimming.CharacterEllipsis };
            Grid.SetColumn(currentOperationText, 1);
            grid.Children.Add(currentOperationText);

            TextBlock statusLabel = new TextBlock { Text = "Status", FontSize = 11, Foreground = Brush("#64748B"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 0, 0) };
            Grid.SetColumn(statusLabel, 2);
            grid.Children.Add(statusLabel);

            operationStatusText = new TextBlock { Text = "Ready", FontSize = 12, Foreground = Brush("#CBD5E1"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 14, 0), TextTrimming = TextTrimming.CharacterEllipsis };
            Grid.SetColumn(operationStatusText, 3);
            grid.Children.Add(operationStatusText);

            Grid progressHost = new Grid { Margin = new Thickness(0, 6, 0, 0), Height = 18 };
            operationProgressBar = new ProgressBar { Minimum = 0, Maximum = 100, Value = 0, Height = 18, Foreground = Brush("#22C55E"), Background = Brush("#1E293B"), BorderBrush = Brush("#334155"), VerticalAlignment = VerticalAlignment.Center };
            progressHost.Children.Add(operationProgressBar);
            operationProgressText = new TextBlock { Text = "0%", FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brush("#F8FAFC"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            progressHost.Children.Add(operationProgressText);
            Grid.SetRow(progressHost, 1);
            Grid.SetColumn(progressHost, 0);
            Grid.SetColumnSpan(progressHost, 4);
            grid.Children.Add(progressHost);

            return grid;
        }

        private void SetOperation(string operation, string status, double percent)
        {
            if (!Dispatcher.CheckAccess())
            {
                Dispatcher.BeginInvoke(new Action(delegate { SetOperation(operation, status, percent); }));
                return;
            }
            if (currentOperationText == null) { return; }
            if (percent < 0) { percent = 0; }
            if (percent > 100) { percent = 100; }
            currentOperationText.Text = operation;
            string percentText = ((int)Math.Round(percent)).ToString() + "%";
            operationStatusText.Text = status;
            operationProgressBar.Value = percent;
            operationProgressText.Text = percentText;
            if (footerStatusText != null)
            {
                footerStatusText.Text = operation + " - " + status;
            }
        }

        private string FormatOperationName(string[] args)
        {
            string action = ArgValue(args, "-Action");
            if (action == "Validate") return "Validate";
            if (action == "Download") return "Download";
            if (action == "GenerateMarquees") return "Generate Marquees";
            if (action == "ConvertMp4ToMp3") return "Convert MP4s to MP3";
            if (action == "AddVideo") return "Add Video";
            if (action == "ImportSource") return "Import Videos";
            if (action == "Search") return "Search";
            if (action == "Clear") return "Clear Videos";
            if (action == "MoveToSsd") return "Move to SSD";
            if (action == "MoveBitLcdArtwork") return "Move BitLCD Artwork";
            return "Task";
        }

        private string FormatCommand(string[] args)
        {
            string action = ArgValue(args, "-Action");
            string value = ArgValue(args, "-Value");
            string limit = ArgValue(args, "-Limit");
            if (action == "Validate") return "Checking setup...";
            if (action == "Download")
            {
                string mediaType = ArgValue(args, "-DownloadMediaType");
                if (mediaType == "Audio") { return "Starting audio downloads..."; }
                string resolution = ArgValue(args, "-Resolution");
                string resolutionText = resolution.Length > 0 ? " at " + resolution + "p" : "";
                return "Starting video downloads" + resolutionText + "...";
            }
            if (action == "ConvertMp4ToMp3") return "Starting MP4 to MP3 conversion...";
            if (action == "AddVideo") return "Adding one video: " + value;
            if (action == "ImportSource") return "Reading playlist or channel: " + value + (limit.Length > 0 ? " (limit: " + limit + ")" : "");
            if (action == "Search") return "Searching YouTube for: " + value + (limit.Length > 0 ? " (limit: " + limit + ")" : "");
            if (action == "Clear") return "Clearing the video list...";
            if (action == "MoveToSsd") return "Moving downloads to SSD folder" + (value.Length > 0 ? ": " + value : "") + "...";
            if (action == "MoveBitLcdArtwork") return "Moving BitLCD artwork...";
            if (action == "GenerateMarquees") return "Generating selected marquee artwork...";
            return "Running task...";
        }

        private string ArgValue(string[] args, string name)
        {
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (args[i] == name) return args[i + 1];
            }
            return "";
        }

        private bool CanCancelOperation(string[] args)
        {
            string action = ArgValue(args, "-Action");
            return action != "MoveToSsd" && action != "MoveBitLcdArtwork";
        }

        private string GetCancelButtonText()
        {
            if (activeOperationAction == "Download") return "Cancel running YouTube Download process";
            if (activeOperationAction == "GenerateMarquees") return "Cancel generating missing MP4 marquees";
            if (activeOperationAction == "SearchPreview" || activeOperationAction == "SourcePreview" || activeOperationAction == "VideoPreview") return "Cancel running YouTube Search process";
            return "Cancel running process";
        }

        private string QuoteArgs(string[] args)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < args.Length; i++)
            {
                if (i > 0) sb.Append(" ");
                sb.Append("\"").Append(args[i].Replace("\"", "\\\"")).Append("\"");
            }
            return sb.ToString();
        }

        private void SetBusy(bool busy)
        {
            if (!Dispatcher.CheckAccess())
            {
                Dispatcher.BeginInvoke(new Action(delegate { SetBusy(busy); }));
                return;
            }
            isRunning = busy;
            foreach (Control control in actionControls)
            {
                control.IsHitTestVisible = !busy;
                control.Focusable = !busy;
                control.Opacity = busy ? 0.55 : 1.0;
            }
            if (cancelButton != null)
            {
                bool showCancel = busy && activeOperationCanCancel;
                cancelButton.Content = GetCancelButtonText();
                cancelButton.Visibility = showCancel ? Visibility.Visible : Visibility.Collapsed;
                cancelButton.IsHitTestVisible = showCancel;
                cancelButton.Focusable = showCancel;
                cancelButton.Opacity = showCancel ? 1.0 : 0.0;
            }
            if (!busy)
            {
                activeOperationCanCancel = false;
                activeOperationAction = "";
                if (footerStatusText != null)
                {
                    footerStatusText.Text = "Done";
                    DispatcherTimerResetStatus();
                }
            }
            Cursor = busy ? Cursors.Wait : null;
        }

        private void AddActionControl(Control control)
        {
            if (control == null) { return; }
            if (!actionControls.Contains(control)) actionControls.Add(control);
        }

        private void DispatcherTimerResetStatus()
        {
            DispatcherTimer timer = new DispatcherTimer();
            timer.Interval = TimeSpan.FromSeconds(3);
            timer.Tick += delegate
            {
                timer.Stop();
                if (!isRunning && footerStatusText != null)
                {
                    footerStatusText.Text = "Ready";
                }
            };
            timer.Start();
        }

        private void ShowConsoleWindow()
        {
            if (consoleWindow != null)
            {
                PositionConsoleWindow();
                consoleWindow.Show();
                consoleWindow.Activate();
                return;
            }

            outputBox = new TextBox { Background = Brush("#050A12"), Foreground = Brush("#D1D5DB"), BorderBrush = Brush("#263241"), FontFamily = new FontFamily("Consolas"), FontSize = 12, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
            consoleWindow = new Window
            {
                Title = "Jukebox Download Wizard Console",
                Width = 720,
                Height = 420,
                MinWidth = 420,
                MinHeight = 220,
                WindowStartupLocation = WindowStartupLocation.Manual,
                Background = Brush("#050A12"),
                Content = outputBox
            };
            PositionConsoleWindow();
            consoleWindow.Closed += delegate
            {
                consoleWindow = null;
                outputBox = null;
            };
            if (File.Exists(guiConsoleLogFile))
            {
                try
                {
                    outputBox.Text = File.ReadAllText(guiConsoleLogFile);
                    outputBox.ScrollToEnd();
                }
                catch
                {
                }
            }
            consoleWindow.Show();
        }

        private void PositionConsoleWindow()
        {
            if (consoleWindow == null) { return; }

            Rect workArea = SystemParameters.WorkArea;
            double consoleLeft = Math.Max(workArea.Left, Left + ActualWidth);
            double availableWidth = workArea.Right - consoleLeft;
            if (availableWidth < consoleWindow.MinWidth)
            {
                availableWidth = Math.Min(720, workArea.Width);
                consoleLeft = workArea.Right - availableWidth;
            }

            consoleWindow.Left = consoleLeft;
            consoleWindow.Top = workArea.Top;
            consoleWindow.Width = availableWidth;
            consoleWindow.Height = workArea.Height;
        }

        private void WriteOutput(string text)
        {
            if (!Dispatcher.CheckAccess())
            {
                Dispatcher.BeginInvoke(new Action(delegate { WriteOutput(text); }));
                return;
            }
            UpdateOperationFromOutput(text);
            try
            {
                Directory.CreateDirectory(consoleLogDir);
                File.AppendAllText(guiConsoleLogFile, "[" + DateTime.Now.ToString("s") + "] " + text + Environment.NewLine, Encoding.UTF8);
            }
            catch
            {
            }
            if (outputBox != null)
            {
                outputBox.AppendText(text + Environment.NewLine);
                outputBox.ScrollToEnd();
            }
        }

        private bool HandleProgressLine(string text)
        {
            if (String.IsNullOrWhiteSpace(text) || !text.StartsWith("PROGRESS|", StringComparison.OrdinalIgnoreCase)) { return false; }
            string[] parts = text.Split('|');
            if (parts.Length < 4) { return true; }

            int current;
            int total;
            if (!Int32.TryParse(parts[2], out current) || !Int32.TryParse(parts[3], out total) || total <= 0) { return true; }

            string detail = "";
            if (parts.Length > 4) { detail = Shorten(parts[4], 54); }
            double pct = ((double)current / (double)total) * 100.0;
            string status = "Processing " + current + " of " + total;
            if (detail.Length > 0) { status += ": " + detail; }
            SetOperation(parts[1], status, pct);
            return true;
        }

        private string Shorten(string value, int maxLength)
        {
            if (String.IsNullOrWhiteSpace(value)) { return ""; }
            value = value.Trim();
            if (value.Length <= maxLength) { return value; }
            if (maxLength <= 3) { return value.Substring(0, maxLength); }
            return value.Substring(0, maxLength - 3) + "...";
        }

        private void UpdateOperationFromOutput(string text)
        {
            if (!isRunning || String.IsNullOrWhiteSpace(text) || operationProgressBar == null) { return; }

            int processingIndex = text.IndexOf("] Processing:", StringComparison.OrdinalIgnoreCase);
            if (processingIndex >= 0)
            {
                string title = text.Substring(processingIndex + "] Processing:".Length).Trim();
                if (title.Length > 0)
                {
                    SetOperation(currentOperationText.Text, "Processing: " + Shorten(title, 96), operationProgressBar.Value);
                    return;
                }
            }

            int bracketStart = text.IndexOf('[');
            int slash = text.IndexOf('/');
            int bracketEnd = text.IndexOf(']');
            if (bracketStart >= 0 && slash > bracketStart && bracketEnd > slash)
            {
                int current;
                int total;
                string left = text.Substring(bracketStart + 1, slash - bracketStart - 1);
                string right = text.Substring(slash + 1, bracketEnd - slash - 1);
                if (Int32.TryParse(left, out current) && Int32.TryParse(right, out total) && total > 0)
                {
                    double pct = ((double)(current - 1) / (double)total) * 100.0;
                    if (pct < 0) { pct = 0; }
                    SetOperation(currentOperationText.Text, "Processing " + current + " of " + total, pct);
                    return;
                }
            }

            if (text.IndexOf("download started", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                SetOperation(currentOperationText.Text, "Downloading", Math.Max(operationProgressBar.Value, 5));
                return;
            }
            if (text.IndexOf("download completed", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                SetOperation(currentOperationText.Text, "Download part complete", Math.Max(operationProgressBar.Value, 10));
                return;
            }
            if (text.StartsWith("Finished.", StringComparison.OrdinalIgnoreCase) ||
                text.StartsWith("Finished moving", StringComparison.OrdinalIgnoreCase) ||
                text.StartsWith("Validation completed", StringComparison.OrdinalIgnoreCase))
            {
                SetOperation(currentOperationText.Text, "Finishing", 100);
            }
        }

        private bool IsSourceUrl(string url)
        {
            return url.IndexOf("list=", StringComparison.OrdinalIgnoreCase) >= 0 ||
                   url.IndexOf("youtube.com/@", StringComparison.OrdinalIgnoreCase) >= 0 ||
                   url.IndexOf("youtube.com/channel/", StringComparison.OrdinalIgnoreCase) >= 0 ||
                   url.IndexOf("youtube.com/c/", StringComparison.OrdinalIgnoreCase) >= 0 ||
                   url.IndexOf("youtube.com/user/", StringComparison.OrdinalIgnoreCase) >= 0 ||
                   url.IndexOf("youtube.com/playlist", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private bool IsYouTubeUrl(string url)
        {
            bool hasHttp = url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase);
            bool hasYouTubeHost = url.IndexOf("youtube.com", StringComparison.OrdinalIgnoreCase) >= 0 || url.IndexOf("youtu.be", StringComparison.OrdinalIgnoreCase) >= 0;
            return hasHttp && hasYouTubeHost;
        }

        private string GetYouTubeId(string url)
        {
            if (String.IsNullOrWhiteSpace(url)) { return ""; }
            System.Text.RegularExpressions.Match match = System.Text.RegularExpressions.Regex.Match(url, @"youtu\.be/([A-Za-z0-9_-]{11})", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (match.Success) { return match.Groups[1].Value; }
            match = System.Text.RegularExpressions.Regex.Match(url, @"[?&]v=([A-Za-z0-9_-]{11})", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (match.Success) { return match.Groups[1].Value; }
            match = System.Text.RegularExpressions.Regex.Match(url, @"/embed/([A-Za-z0-9_-]{11})", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (match.Success) { return match.Groups[1].Value; }
            return "";
        }

        private string FormatElapsed(TimeSpan elapsed)
        {
            if (elapsed.TotalHours >= 1)
            {
                return ((int)elapsed.TotalHours) + ":" + elapsed.Minutes.ToString("00") + ":" + elapsed.Seconds.ToString("00");
            }
            return ((int)elapsed.TotalMinutes) + ":" + elapsed.Seconds.ToString("00");
        }

        private void OpenFolder(string path)
        {
            Directory.CreateDirectory(path);
            Process.Start("explorer.exe", "\"" + path + "\"");
        }

        private Border PanelBorder()
        {
            return new Border { Background = Brush("#111827"), BorderBrush = Brush("#263241"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), Padding = new Thickness(12) };
        }

        private GridSplitter VerticalSplitter()
        {
            return new GridSplitter
            {
                Width = 8,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
                Background = Brush("#0B1020"),
                ShowsPreview = true,
                ResizeDirection = GridResizeDirection.Columns,
                ResizeBehavior = GridResizeBehavior.PreviousAndNext,
                Cursor = Cursors.SizeWE
            };
        }

        private GridSplitter HorizontalSplitter()
        {
            return new GridSplitter
            {
                Height = 8,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
                Background = Brush("#0B1020"),
                ShowsPreview = true,
                ResizeDirection = GridResizeDirection.Rows,
                ResizeBehavior = GridResizeBehavior.PreviousAndNext,
                Cursor = Cursors.SizeNS
            };
        }

        private TextBlock Heading(string text)
        {
            return new TextBlock { Text = text, FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 0, 0, 10) };
        }

        private TextBlock SectionTitle(string text)
        {
            return new TextBlock { Text = text, FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Brush("#E5E7EB"), Margin = new Thickness(0, 0, 0, 0) };
        }

        private TextBlock Muted(string text)
        {
            return new TextBlock { Text = text, Foreground = Brush("#9CA3AF") };
        }

        private Separator Separator()
        {
            return new Separator { Margin = new Thickness(0, 16, 0, 14) };
        }

        private TextBox InputBox()
        {
            return new TextBox { Height = 30, Background = Brush("#0F172A"), Foreground = Brush("#E5E7EB"), CaretBrush = Brush("#E5E7EB"), BorderBrush = Brush("#334155"), Padding = new Thickness(6, 3, 6, 3) };
        }

        private Button Button(string text, double width, double height)
        {
            Button button = new Button { Content = text, Height = height, Margin = new Thickness(6, 0, 0, 0), Background = Brush("#1F2937"), Foreground = Brush("#E5E7EB"), BorderBrush = Brush("#374151"), BorderThickness = new Thickness(1), Padding = new Thickness(10, 4, 10, 4), Cursor = Cursors.Hand };
            if (!Double.IsNaN(width)) button.Width = width;
            ApplyButtonTemplate(button, 0);
            return button;
        }

        private Button RoundedButton(string text, double width, double height, double radius)
        {
            Button button = Button(text, width, height);
            ApplyButtonTemplate(button, radius);
            return button;
        }

        private void ApplyButtonTemplate(Button button, double radius)
        {
            ControlTemplate template = new ControlTemplate(typeof(System.Windows.Controls.Button));
            FrameworkElementFactory border = new FrameworkElementFactory(typeof(Border));
            border.Name = "ButtonChrome";
            border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(System.Windows.Controls.Button.BackgroundProperty));
            border.SetValue(Border.BorderBrushProperty, new TemplateBindingExtension(System.Windows.Controls.Button.BorderBrushProperty));
            border.SetValue(Border.BorderThicknessProperty, new TemplateBindingExtension(System.Windows.Controls.Button.BorderThicknessProperty));
            border.SetValue(Border.CornerRadiusProperty, new CornerRadius(radius));
            FrameworkElementFactory content = new FrameworkElementFactory(typeof(ContentPresenter));
            content.Name = "ButtonContent";
            content.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            content.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            content.SetValue(ContentPresenter.RecognizesAccessKeyProperty, true);
            content.SetValue(FrameworkElement.MarginProperty, new TemplateBindingExtension(System.Windows.Controls.Button.PaddingProperty));
            content.SetValue(System.Windows.Documents.TextElement.ForegroundProperty, new TemplateBindingExtension(System.Windows.Controls.Button.ForegroundProperty));
            border.AppendChild(content);
            template.VisualTree = border;

            Trigger hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
            hover.Setters.Add(new Setter(Border.BackgroundProperty, Brush("#CBD5E1"), "ButtonChrome"));
            hover.Setters.Add(new Setter(Border.BorderBrushProperty, Brush("#E2E8F0"), "ButtonChrome"));
            hover.Setters.Add(new Setter(System.Windows.Documents.TextElement.ForegroundProperty, Brush("#0F172A"), "ButtonContent"));
            template.Triggers.Add(hover);

            Trigger pressed = new Trigger { Property = System.Windows.Controls.Button.IsPressedProperty, Value = true };
            pressed.Setters.Add(new Setter(Border.BackgroundProperty, Brush("#94A3B8"), "ButtonChrome"));
            pressed.Setters.Add(new Setter(Border.BorderBrushProperty, Brush("#CBD5E1"), "ButtonChrome"));
            pressed.Setters.Add(new Setter(System.Windows.Documents.TextElement.ForegroundProperty, Brush("#0B1020"), "ButtonContent"));
            template.Triggers.Add(pressed);

            Trigger disabled = new Trigger { Property = UIElement.IsEnabledProperty, Value = false };
            disabled.Setters.Add(new Setter(UIElement.OpacityProperty, 0.55, "ButtonChrome"));
            disabled.Setters.Add(new Setter(System.Windows.Documents.TextElement.ForegroundProperty, Brush("#94A3B8"), "ButtonContent"));
            template.Triggers.Add(disabled);

            button.Template = template;
        }

        private Button TwoLineButton(string ratio, string mode)
        {
            StackPanel label = new StackPanel { Orientation = Orientation.Vertical, VerticalAlignment = VerticalAlignment.Center };
            label.Children.Add(new TextBlock { Text = ratio, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Brush("#F8FAFC"), HorizontalAlignment = HorizontalAlignment.Center, TextAlignment = TextAlignment.Center });
            label.Children.Add(new TextBlock { Text = mode, FontSize = 10, Foreground = Brush("#CBD5E1"), HorizontalAlignment = HorizontalAlignment.Center, TextAlignment = TextAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });

            Button button = Button("", double.NaN, 44);
            button.Content = label;
            button.Padding = new Thickness(4, 3, 4, 3);
            return button;
        }

        private Image Image(string fileName, double width, double height, Thickness margin)
        {
            return Image(fileName, width, height, margin, Int32Rect.Empty);
        }

        private Image Image(string fileName, double width, double height, Thickness margin, Int32Rect crop)
        {
            Image image = new Image { Width = width, Height = height, Stretch = Stretch.Uniform, Margin = margin, VerticalAlignment = VerticalAlignment.Center };
            string path = Path.Combine(assetsDir, "images", fileName);
            if (File.Exists(path))
            {
                BitmapImage bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.UriSource = new Uri(path, UriKind.Absolute);
                bitmap.EndInit();
                image.Source = crop == Int32Rect.Empty ? (ImageSource)bitmap : new CroppedBitmap(bitmap, crop);
            }
            return image;
        }

        private Brush Brush(string hex)
        {
            return (Brush)new BrushConverter().ConvertFromString(hex);
        }
    }
}
