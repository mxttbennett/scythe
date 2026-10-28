import Foundation
import Testing
@testable import Scythe

@Suite("Linear link routing")
struct LinearLinkTests {
    private func desktop(_ text: String) -> String? {
        LinearLink.desktopURL(for: URL(string: text)!)?.absoluteString
    }

    @Test("an issue link becomes the same path on the linear scheme")
    func issueLink() {
        // Act & Assert
        #expect(desktop("https://linear.app/acme/issue/COG-1553/fix-the-page") == "linear://acme/issue/COG-1553/fix-the-page")
    }

    @Test("an issue link without a title slug still routes")
    func issueWithoutSlug() {
        // Act & Assert
        #expect(desktop("https://linear.app/acme/issue/COG-1553") == "linear://acme/issue/COG-1553")
    }

    @Test("a plain http link routes too")
    func httpLink() {
        // Act & Assert
        #expect(desktop("http://linear.app/acme/issue/COG-1553") == "linear://acme/issue/COG-1553")
    }

    @Test("a query and a fragment survive")
    func queryAndFragment() {
        // Act & Assert
        #expect(desktop("https://linear.app/acme/issue/COG-1553/x?comment=abc#top") == "linear://acme/issue/COG-1553/x?comment=abc#top")
    }

    @Test("the host is matched whatever its case")
    func hostCase() {
        // Act & Assert
        #expect(desktop("https://Linear.App/acme/issue/COG-1553") == "linear://acme/issue/COG-1553")
    }

    @Test("projects and documents route as well")
    func otherWorkspacePages() {
        // Act & Assert
        #expect(desktop("https://linear.app/acme/project/launch-abc123") == "linear://acme/project/launch-abc123")
        #expect(desktop("https://linear.app/acme/document/spec-abc123") == "linear://acme/document/spec-abc123")
    }

    @Test("other sites are left alone")
    func otherHosts() {
        // Act & Assert
        #expect(desktop("https://github.com/acme/repo/issues/1") == nil)
        #expect(desktop("https://notlinear.app/acme/issue/COG-1") == nil)
        #expect(desktop("https://linear.app.example.com/acme/issue/COG-1") == nil)
        #expect(desktop("https://example.com/linear.app/acme/issue/COG-1") == nil)
    }

    @Test("pages that are not inside a workspace stay on the web")
    func marketingPages() {
        // Act & Assert
        #expect(desktop("https://linear.app/") == nil)
        #expect(desktop("https://linear.app/docs") == nil)
        #expect(desktop("https://linear.app/acme") == nil)
        #expect(desktop("https://linear.app/changelog/2026-01-01-news") == nil)
    }

    @Test("a link already on the linear scheme is not routed again")
    func alreadyDesktop() {
        // Act & Assert
        #expect(desktop("linear://acme/issue/COG-1553") == nil)
    }

    @Test("without the desktop app a link opens as it was")
    func notInstalled() {
        // Arrange
        let url = URL(string: "https://linear.app/acme/issue/COG-1553")!

        // Act & Assert
        #expect(LinearLink.route(url, isInstalled: false) == nil)
    }

    @Test("with the desktop app a Linear link is routed to it")
    func installed() {
        // Arrange
        let url = URL(string: "https://linear.app/acme/issue/COG-1553")!

        // Act & Assert
        #expect(LinearLink.route(url, isInstalled: true)?.absoluteString == "linear://acme/issue/COG-1553")
    }

    @Test("with the desktop app a link to another site still opens normally")
    func installedOtherSite() {
        // Arrange
        let url = URL(string: "https://example.com/a")!

        // Act & Assert
        #expect(LinearLink.route(url, isInstalled: true) == nil)
    }
}
