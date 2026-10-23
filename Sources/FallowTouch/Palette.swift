#if os(iOS)
import UIKit

/// Colors for text and chrome, the same as the Mac's, chosen to sit on the soil-toned backgrounds.
enum Palette {
    static let text = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.86, green: 0.83, blue: 0.78, alpha: 1)
            : UIColor(red: 0.21, green: 0.19, blue: 0.16, alpha: 1)
    }
    static let secondary = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.86, green: 0.83, blue: 0.78, alpha: 0.45)
            : UIColor(red: 0.21, green: 0.19, blue: 0.16, alpha: 0.45)
    }
    /// A loamy brown for the insertion point and selection handles.
    static let caret = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.80, green: 0.56, blue: 0.38, alpha: 1)
            : UIColor(red: 0.60, green: 0.36, blue: 0.21, alpha: 1)
    }
}
#endif
