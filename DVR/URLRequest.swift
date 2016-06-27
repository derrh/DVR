import Foundation

extension URLRequest {
    var dictionary: [String: AnyObject] {
        var dictionary = [String: AnyObject]()

        if let method = httpMethod {
            dictionary["method"] = method
        }

        if let url = url?.absoluteString {
            dictionary["url"] = url
        }

        if let headers = allHTTPHeaderFields {
            dictionary["headers"] = headers
        }

        if let data = httpBody, body = Interaction.encodeBody(data, headers: allHTTPHeaderFields) {
            dictionary["body"] = body
        }

        return dictionary
    }
}


extension URLRequest {
    func requestByAppendingHeaders(_ headers: [NSObject: AnyObject]) -> URLRequest {
        var request = self
        request.append(headers: headers)
        return request
    }

    func requestWithBody(_ body: Data) -> URLRequest {
        var request = self
        request.httpBody = body
        return request
    }
}


extension URLRequest {
    init(dictionary: [String: AnyObject]) {
        guard let string = dictionary["url"] as? String, url = URL(string: string) else { fatalError() }
        
        self.init(url: url)

        if let method = dictionary["method"] as? String {
            httpMethod = method
        }

        if let headers = dictionary["headers"] as? [String: String] {
            allHTTPHeaderFields = headers
        }

        if let body = dictionary["body"] {
            httpBody = Interaction.dencodeBody(body, headers: allHTTPHeaderFields)
        }
    }
}


extension URLRequest {
    mutating func append(headers: [NSObject: AnyObject]) {
        var existingHeaders = allHTTPHeaderFields ?? [:]

        headers.forEach { header in
            guard let key = header.0 as? String, value = header.1 as? String where existingHeaders[key] == nil else {
                return
            }

            existingHeaders[key] = value
        }

        allHTTPHeaderFields = existingHeaders
    }
}
