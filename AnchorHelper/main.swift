import Foundation

// @MainActor init requires dispatch onto the main actor from the top-level context.
Task { @MainActor in
    let app = HelperApp()
    await app.run()
}
RunLoop.main.run()
