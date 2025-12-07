import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var pendingFilePath: String?

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    NSLog("=== App Did Finish Launching ===")

    // Setup method channel with a delay to ensure Flutter is ready
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.setupMethodChannel()
    }

    NSLog("App delegate initialized")
  }

  private func setupMethodChannel() {
    NSLog("Setting up method channel...")
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      methodChannel = FlutterMethodChannel(
        name: "com.gpmt/file_handler",
        binaryMessenger: controller.engine.binaryMessenger
      )
      NSLog("Method channel created successfully")

      // Send pending file if any
      if let filePath = pendingFilePath {
        NSLog("Sending pending file: %@", filePath)
        sendFileToFlutter(filePath)
        pendingFilePath = nil
      }
    } else {
      NSLog("ERROR: Could not get FlutterViewController, retrying...")
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
    NSLog("=== AppDelegate openFile ===")
    NSLog("File to open: %@", filename)
    sendFileToFlutter(filename)

    // Call super to ensure proper handling
    let result = super.application(sender, openFile: filename)
    NSLog("Super returned: %@", result ? "true" : "false")
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    NSLog("=== AppDelegate openFiles ===")
    NSLog("Files to open: %@", filenames.joined(separator: ", "))

    // Handle multiple files (open the first one)
    if let firstFile = filenames.first {
      sendFileToFlutter(firstFile)
    }

    // Call super
    super.application(sender, openFiles: filenames)
  }

  private func sendFileToFlutter(_ filePath: String) {
    NSLog("Sending to Flutter: %@", filePath)
    if let channel = methodChannel {
      channel.invokeMethod("openFile", arguments: filePath)
      NSLog("Invoked method on channel successfully")
    } else {
      NSLog("Method channel not ready yet, storing as pending: %@", filePath)
      pendingFilePath = filePath
      // Try to setup the channel again
      setupMethodChannel()
    }
  }
}
