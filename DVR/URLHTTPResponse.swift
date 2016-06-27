import Foundation

// There isn't a mutable NSHTTPURLResponse, so we have to make our own.
class URLHTTPResponse: HTTPURLResponse {

    // MARK: - Properties

    private var _URL: Foundation.URL?
    override var url: Foundation.URL? {
        get {
            return _URL ?? super.url
        }

        set {
            _URL = newValue
        }
    }

    private var _statusCode: Int?
    override var statusCode: Int {
        get {
            return _statusCode ?? super.statusCode
        }

        set {
            _statusCode = newValue
        }
    }

    private var _allHeaderFields: [NSObject : AnyObject]?
    override var allHeaderFields: [NSObject : AnyObject] {
        get {
            return _allHeaderFields ?? super.allHeaderFields
        }

        set {
            _allHeaderFields = newValue
        }
    }
}


extension HTTPURLResponse {
    override var dictionary: [String: AnyObject] {
        var dictionary = super.dictionary

        dictionary["headers"] = allHeaderFields
        dictionary["status"] = statusCode

        return dictionary
    }
}


extension URLHTTPResponse {
    convenience init(dictionary: [String: AnyObject]) {
        self.init()

        if let string = dictionary["url"] as? String, url = Foundation.URL(string: string) {
            self.url = url
        }

        if let headers = dictionary["headers"] as? [String: String] {
            allHeaderFields = headers
        }

        if let status = dictionary["status"] as? Int {
            statusCode = status
        }
    }
}
