import Foundation

// There isn't a mutable NSURLResponse, so we have to make our own.
class DVRURLResponse: Foundation.URLResponse {
    private var _url: Foundation.URL?
    override var url: Foundation.URL? {
        get {
            return _url ?? super.url
        }

        set {
            _url = newValue
        }
    }
}


extension Foundation.URLResponse {
    var dictionary: [String: AnyObject] {
        if let url = url?.absoluteString {
            return ["url": url]
        }

        return [:]
    }
}


extension DVRURLResponse {
    convenience init(dictionary: [String: AnyObject]) {
        self.init()

        if let string = dictionary["url"] as? String, url = Foundation.URL(string: string) {
            self.url = url
        }
    }
}
