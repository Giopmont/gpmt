import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var pendingFilePath: String?

  private func setupMethodChannel() {
    if methodChannel != nil {
      return
    }

    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.setupMethodChannel()
      }
      return
    }

    methodChannel = FlutterMethodChannel(
      name: "com.gpmt/file_handler",
      binaryMessenger: controller.engine.binaryMessenger
    )

    if let filePath = pendingFilePath {
      pendingFilePath = nil
      sendFileToFlutter(filePath)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    sendFileToFlutter(filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    if let firstFile = filenames.first {
      sendFileToFlutter(firstFile)
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.isFileURL {
      sendFileToFlutter(url.path)
      break
    }
  }

  private func sendFileToFlutter(_ filePath: String) {
    if let channel = methodChannel {
      channel.invokeMethod("openFile", arguments: filePath)
      return
    }

    pendingFilePath = filePath
    setupMethodChannel()
  }
}
