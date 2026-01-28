import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var pendingFilePath: String?

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    NSLog("=== GPMT App Did Finish Launching ===")
    
    // Check for file in command line arguments (alternative way macOS passes files)
    let args = ProcessInfo.processInfo.arguments
    NSLog("GPMT Command line args: %@", args.joined(separator: ", "))
    
    // Skip first argument (app path), look for file paths
    for arg in args.dropFirst() {
      if !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: arg) {
        NSLog("GPMT Found file in args: %@", arg)
        pendingFilePath = arg
        break
      }
    }

    // Setup method channel with a delay to ensure Flutter and plugins are ready
    // MainFlutterWindow registers plugins with 0.3s delay, so we wait longer here
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.setupMethodChannel()
    }

    NSLog("GPMT App delegate initialized")
  }

  private func setupMethodChannel() {
    NSLog("GPMT Setting up method channel...")
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      methodChannel = FlutterMethodChannel(
        name: "com.gpmt/file_handler",
        binaryMessenger: controller.engine.binaryMessenger
      )
      NSLog("GPMT Method channel created successfully")

      // Send pending file if any
      if let filePath = pendingFilePath {
        NSLog("GPMT Sending pending file: %@", filePath)
        sendFileToFlutter(filePath)
        pendingFilePath = nil
      }
    } else {
      NSLog("GPMT ERROR: Could not get FlutterViewController, retrying...")
      // Retry after a short delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.setupMethodChannel()
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Handle file opening from Finder (double-click or "Open With")
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    NSLog("=== GPMT AppDelegate openFile ===")
    NSLog("GPMT File to open: %@", filename)
    sendFileToFlutter(filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    NSLog("=== GPMT AppDelegate openFiles ===")
    NSLog("GPMT Files to open: %@", filenames.joined(separator: ", "))

    // Handle multiple files (open the first one)
    if let firstFile = filenames.first {
      sendFileToFlutter(firstFile)
    }

    // Tell macOS we handled the files
    sender.reply(toOpenOrPrint: .success)
  }

  // Handle URLs (file:// scheme)
  override func application(_ application: NSApplication, open urls: [URL]) {
    NSLog("=== GPMT AppDelegate open URLs ===")
    for url in urls {
      NSLog("GPMT URL: %@", url.absoluteString)
      if url.isFileURL {
        sendFileToFlutter(url.path)
        break
      }
    }
  }

  private func sendFileToFlutter(_ filePath: String) {
    NSLog("GPMT Sending to Flutter: %@", filePath)
    if let channel = methodChannel {
      channel.invokeMethod("openFile", arguments: filePath)
      NSLog("GPMT Invoked method on channel successfully")
    } else {
      NSLog("GPMT Method channel not ready yet, storing as pending: %@", filePath)
      pendingFilePath = filePath
      // Try to setup the channel again
      setupMethodChannel()
    }
  }
}
