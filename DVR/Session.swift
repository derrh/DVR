import Foundation

public class Session: URLSession {

    // MARK: - Properties

    public var outputDirectory: String
    public let cassetteName: String
    public let backingSession: URLSession
    public var recordingEnabled = true

    private let testBundle: Bundle

    private var recording = false
    private var needsPersistence = false
    private var outstandingTasks = [URLSessionTask]()
    private var completedInteractions = [Interaction]()
    private var completionBlock: ((Void) -> Void)?

    override public var delegate: URLSessionDelegate? {
        return backingSession.delegate
    }

    // MARK: - Initializers

    public init(outputDirectory: String = "~/Desktop/DVR/", cassetteName: String, testBundle: Bundle = Bundle.allBundles.filter() { $0.bundlePath.hasSuffix(".xctest") }.first!, backingSession: URLSession = URLSession.shared) {
        self.outputDirectory = outputDirectory
        self.cassetteName = cassetteName
        self.testBundle = testBundle
        self.backingSession = backingSession
        super.init()
    }


    // MARK: - NSURLSession

    public override func dataTask(with request: URLRequest) -> URLSessionDataTask {
        return addDataTask(request)
    }

    public override func dataTask(with request: URLRequest, completionHandler: (Data?, URLResponse?, NSError?) -> Void) -> URLSessionDataTask {
        return addDataTask(request, completionHandler: completionHandler)
    }

    public override func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
        return addDownloadTask(request)
    }

    public override func downloadTask(with request: URLRequest, completionHandler: (URL?, URLResponse?, NSError?) -> Void) -> URLSessionDownloadTask {
        return addDownloadTask(request, completionHandler: completionHandler)
    }

    public override func uploadTask(with request: URLRequest, from bodyData: Data) -> URLSessionUploadTask {
        return addUploadTask(request, fromData: bodyData)
    }

    public override func uploadTask(with request: URLRequest, from bodyData: Data?, completionHandler: (Data?, URLResponse?, NSError?) -> Void) -> URLSessionUploadTask {
        return addUploadTask(request, fromData: bodyData, completionHandler: completionHandler)
    }

    public override func uploadTask(with request: URLRequest, fromFile fileURL: URL) -> URLSessionUploadTask {
        let data = try! Data(contentsOf: fileURL)
        return addUploadTask(request, fromData: data)
    }

    public override func uploadTask(with request: URLRequest, fromFile fileURL: URL, completionHandler: (Data?, URLResponse?, NSError?) -> Void) -> URLSessionUploadTask {
        let data = try! Data(contentsOf: fileURL)
        return addUploadTask(request, fromData: data, completionHandler: completionHandler)
    }

    public override func invalidateAndCancel() {
        recording = false
        outstandingTasks.removeAll()
        backingSession.invalidateAndCancel()
    }


    // MARK: - Recording

    /// You don’t need to call this method if you're only recoding one request.
    public func beginRecording() {
        if recording {
            return
        }

        recording = true
        needsPersistence = false
        outstandingTasks = []
        completedInteractions = []
        completionBlock = nil
    }

    /// This only needs to be called if you call `beginRecording`. `completion` will be called on the main queue after
    /// the completion block of the last task is called. `completion` is useful for fulfilling an expectation you setup
    /// before calling `beginRecording`.
    public func endRecording(_ completion: ((Void) -> Void)? = nil) {
        if !recording {
            return
        }

        recording = false
        completionBlock = completion

        if outstandingTasks.count == 0 {
            finishRecording()
        }
    }


    // MARK: - Internal

    var cassette: Cassette? {
        guard let path = testBundle.pathForResource(cassetteName, ofType: "json"),
            data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            raw = try? JSONSerialization.jsonObject(with: data, options: []),
            json = raw as? [String: AnyObject]
        else { return nil }

        return Cassette(dictionary: json)
    }

    func finishTask(_ task: URLSessionTask, interaction: Interaction, playback: Bool) {
        needsPersistence = needsPersistence || !playback

        if let index = outstandingTasks.index(of: task) {
            outstandingTasks.remove(at: index)
        }

        completedInteractions.append(interaction)

        if !recording && outstandingTasks.count == 0 {
            finishRecording()
        }

        if let delegate = delegate as? URLSessionDataDelegate, task = task as? URLSessionDataTask, data = interaction.responseData {
            delegate.urlSession?(self, dataTask: task, didReceive: data as Data)
        }

        if let delegate = delegate as? URLSessionTaskDelegate {
            delegate.urlSession?(self, task: task, didCompleteWithError: nil)
        }
    }


    // MARK: - Private

    private func addDataTask(_ request: URLRequest, completionHandler: ((Data?, Foundation.URLResponse?, NSError?) -> Void)? = nil) -> URLSessionDataTask {
        let modifiedRequest = backingSession.configuration.httpAdditionalHeaders.map(request.requestByAppendingHeaders) ?? request
        let task = SessionDataTask(session: self, request: modifiedRequest, completion: completionHandler)
        addTask(task)
        return task
    }

    private func addDownloadTask(_ request: URLRequest, completionHandler: SessionDownloadTask.Completion? = nil) -> URLSessionDownloadTask {
        let modifiedRequest = backingSession.configuration.httpAdditionalHeaders.map(request.requestByAppendingHeaders) ?? request
        let task = SessionDownloadTask(session: self, request: modifiedRequest, completion: completionHandler)
        addTask(task)
        return task
    }

    private func addUploadTask(_ request: URLRequest, fromData data: Data?, completionHandler: SessionUploadTask.Completion? = nil) -> URLSessionUploadTask {
        var modifiedRequest = backingSession.configuration.httpAdditionalHeaders.map(request.requestByAppendingHeaders) ?? request
        modifiedRequest = data.map(modifiedRequest.requestWithBody) ?? modifiedRequest
        let task = SessionUploadTask(session: self, request: modifiedRequest, completion: completionHandler)
        addTask(task.dataTask)
        return task
    }

    private func addTask(_ task: URLSessionTask) {
        let shouldRecord = !recording
        if shouldRecord {
            beginRecording()
        }

        outstandingTasks.append(task)

        if shouldRecord {
            endRecording()
        }
    }

    private func persist(_ interactions: [Interaction]) {
        defer {
            abort()
        }

        // Create directory
        let outputDirectory = (self.outputDirectory as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDirectory) {
			do {
				try fileManager.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true, attributes: nil)
			} catch {
				print("[DVR] Failed to create cassettes directory.")
			}
        }

        let cassette = Cassette(name: cassetteName, interactions: interactions)

        // Persist


        do {
            let outputPath = ((outputDirectory as NSString).appendingPathComponent(cassetteName) as NSString).appendingPathExtension("json")!
            let data = try JSONSerialization.data(withJSONObject: cassette.dictionary, options: [.prettyPrinted])

            // Add trailing new line
            guard var string = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else {
                print("[DVR] Failed to persist cassette.")
                return
            }
            string = string.appending("\n")

            if let data = string.data(using: String.Encoding.utf8.rawValue) {
                try? data.write(to: URL(fileURLWithPath: outputPath), options: [.atomic])
                print("[DVR] Persisted cassette at \(outputPath). Please add this file to your test target")
            }

            print("[DVR] Failed to persist cassette.")
        } catch {
            print("[DVR] Failed to persist cassette.")
        }
    }

    private func finishRecording() {
        if needsPersistence {
            persist(completedInteractions)
        }

        // Clean up
        completedInteractions = []

        // Call session’s completion block
        completionBlock?()
    }
}
