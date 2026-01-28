import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Delay plugin registration to ensure FlutterView is fully ready
    // This fixes EXC_BAD_ACCESS crash in irondash_engine_context/super_native_extensions
    // when the app is launched via file association (double-click on archive file)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      RegisterGeneratedPlugins(registry: flutterViewController)
    }

    super.awakeFromNib()
  }
}
