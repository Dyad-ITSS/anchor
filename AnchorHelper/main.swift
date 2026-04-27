import Foundation

let app = try! HelperApp()
Task { await app.run() }
RunLoop.main.run()
