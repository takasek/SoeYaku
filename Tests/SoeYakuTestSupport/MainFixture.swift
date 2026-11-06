import CoreGraphics
import Foundation

/// The three-page document that the extractor tests and the end-to-end tests both use.
public enum MainFixture {
    private typealias Block = FixturePDF.Block

    private static let leftColumn = CGRect(x: 72, y: 100, width: 220, height: 570)
    private static let rightColumn = CGRect(x: 320, y: 100, width: 220, height: 570)

    private static let leftText =
        "Machine translation has improved quickly over the last decade. "
        + "The \u{FB01}rst systems relied on hand written rules and large dictionaries. "
        + "Modern systems learn from parallel text, and the quality of the transla-\n"
        + "tion depends mostly on the amount of data. "
        + "A good reader wants to follow the original text while the"

    private static let rightText =
        "translation keeps pace with the page. "
        + "Therefore the whole document is translated before reading begins. "
        + "Each sentence is shown beside its source so that the reader can check the meaning quickly. "
        + "The window follows the position of the reader and highlights the sentence that is currently"

    private static func running(_ pageNumber: Int) -> [Block] {
        [
            Block(text: "Running Header", rect: CGRect(x: 72, y: 745, width: 468, height: 20), fontSize: 10),
            Block(text: "\(pageNumber)", rect: CGRect(x: 290, y: 30, width: 40, height: 20), fontSize: 10),
        ]
    }

    /// Three pages: a title and two columns (page 1), a sentence continued from page 1 and a heading (page 2), one paragraph (page 3).
    /// With `rightColumnFirst` the right column is drawn into the PDF before the left one.
    public static func write(rightColumnFirst: Bool, title: String? = "Fixture Title") throws -> URL {
        let titleBlock = Block(text: "A Study of Document Translation", rect: CGRect(x: 72, y: 690, width: 468, height: 40), fontSize: 20)
        let left = Block(text: leftText, rect: leftColumn)
        let right = Block(text: rightText, rect: rightColumn)
        let page1 = running(1) + [titleBlock] + (rightColumnFirst ? [right, left] : [left, right])
        let page2 =
            running(2) + [
                Block(text: "visible in the preview application. Scrolling the document moves the highlight.", rect: CGRect(x: 72, y: 690, width: 468, height: 20)),
                Block(text: "Results", rect: CGRect(x: 72, y: 650, width: 468, height: 28), fontSize: 16),
                Block(
                    text: "The system translated every sentence in the test document. "
                        + "Most sentences were translated correctly with an e\u{FB03}cient model. "
                        + "Nothing was lost between the pages.",
                    rect: CGRect(x: 72, y: 520, width: 468, height: 110)),
            ]
        let page3 =
            running(3) + [
                Block(
                    text: "This short page closes the example. It has only one paragraph with two sentences.",
                    rect: CGRect(x: 72, y: 600, width: 468, height: 100))
            ]
        return try FixturePDF.writeTemporary(pages: [page1, page2, page3], title: title, name: "main")
    }
}
