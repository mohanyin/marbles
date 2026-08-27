import AppKit

enum IdentitySheet {
    static let perFamily = 12
    static let columns = 6

    static func write(using renderer: MarbleRenderer, to directory: URL) -> [URL] {
        let sections = (Identity.minColors...Identity.maxColors).map { count in
            MarbleSheetSection(title: "\(count) colors", seeds: Identity.seeds(colorCount: count, count: perFamily))
        }
        var urls: [URL] = []
        let jobs: [(name: String, tile: CGFloat, background: NSColor)] = [
            ("marbles-identities-black.png", 72, .black),
            ("marbles-identities-white.png", 72, .white),
            ("marbles-identities-36pt-black.png", 36, .black),
            ("marbles-identities-36pt-white.png", 36, .white),
        ]
        for job in jobs {
            guard let image = renderer.renderSheet(
                sections: sections,
                tilePoints: job.tile,
                columns: columns,
                background: job.background,
                scale: 2
            ) else { continue }
            let url = directory.appendingPathComponent(job.name)
            if writePNG(image, to: url) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func writePNG(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
