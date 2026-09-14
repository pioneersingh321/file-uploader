import Foundation
import Capacitor
import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

@objc(FileUploaderPlugin)
public class FileUploaderPlugin: CAPPlugin {
    
    private var activeDownloaders: [String: FileDownloader] = [:]
    private let downloadersLock = NSLock()
    
    private var activeOpeners: [String: FileOpenerSession] = [:]
    private let openersLock = NSLock()
    
    // MARK: - Upload Files
    
    @objc public func uploadFiles(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        guard let urlString = call.getString("url"), !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resolveReject(call, "url is required")
            return
        }
        
        guard let filesArray = call.getArray("files"), !filesArray.isEmpty else {
            resolveReject(call, "files is required and cannot be empty")
            return
        }
        
        let token = call.getString("token") ?? ""
        let fileKey = call.getString("fileKey") ?? "files[]"
        let data = call.getObject("data")
        
        guard let targetUrl = URL(string: urlString) else {
            resolveReject(call, "Invalid URL")
            return
        }
        
        var filesToUpload: [(key: String, fileName: String, fileUrl: URL, mimeType: String)] = []
        
        for (index, item) in filesArray.enumerated() {
            guard let fileItem = item as? [String: Any],
                  let filePath = fileItem["path"] as? String,
                  !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                resolveReject(call, "Invalid or missing 'path' for file at index \(index)")
                return
            }
            
            guard let fileUrl = getFileUrl(filePath) else {
                resolveReject(call, "Invalid file path at index \(index): \(filePath)")
                return
            }
            
            if !FileManager.default.fileExists(atPath: fileUrl.path) {
                resolveReject(call, "File does not exist at index \(index): \(fileUrl.path)")
                return
            }
            
            let fileName = fileUrl.lastPathComponent
            let mimeType = getMimeType(from: fileUrl)
            
            filesToUpload.append((key: fileKey, fileName: fileName, fileUrl: fileUrl, mimeType: mimeType))
        }
        
        if filesToUpload.isEmpty {
            resolveReject(call, "No valid files to upload found")
            return
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: targetUrl)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let postBody: Data
        do {
            postBody = try createMultipartBody(parameters: data, boundary: boundary, files: filesToUpload)
        } catch {
            resolveReject(call, "Failed to create multipart request: \(error.localizedDescription)")
            return
        }
        
        request.setValue("\(postBody.count)", forHTTPHeaderField: "Content-Length")
        
        let task = URLSession.shared.uploadTask(with: request, from: postBody) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.resolveSuccess(call, [
                        "status": false,
                        "output": error.localizedDescription
                    ])
                    return
                }
                
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                let isSuccess = statusCode >= 200 && statusCode < 300
                
                var output: Any = [:]
                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                        output = json
                    } else if let rawString = String(data: data, encoding: .utf8) {
                        output = ["raw": rawString]
                    }
                }
                
                self?.resolveSuccess(call, [
                    "status": isSuccess,
                    "httpStatus": statusCode,
                    "output": output
                ])
            }
        }
        task.resume()
    }
    
    // MARK: - Upload File
    
    @objc public func uploadFile(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        guard let urlString = call.getString("url"), !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resolveReject(call, "url is required")
            return
        }
        guard let file = call.getString("file"), !file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resolveReject(call, "file is required")
            return
        }
        
        let token = call.getString("token") ?? ""
        let fileKey = call.getString("fileKey") ?? "file"
        let data = call.getObject("data")
        
        guard let targetUrl = URL(string: urlString) else {
            resolveReject(call, "Invalid URL")
            return
        }
        
        guard let fileUrl = getFileUrl(file) else {
            resolveReject(call, "Invalid file path")
            return
        }
        
        if !FileManager.default.fileExists(atPath: fileUrl.path) {
            resolveReject(call, "File does not exist: \(fileUrl.path)")
            return
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: targetUrl)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let fileName = fileUrl.lastPathComponent
        let mimeType = getMimeType(from: fileUrl)
        let files = [(key: fileKey, fileName: fileName, fileUrl: fileUrl, mimeType: mimeType)]
        
        let postBody: Data
        do {
            postBody = try createMultipartBody(parameters: data, boundary: boundary, files: files)
        } catch {
            resolveReject(call, "Failed to create multipart request: \(error.localizedDescription)")
            return
        }
        
        request.setValue("\(postBody.count)", forHTTPHeaderField: "Content-Length")
        
        let task = URLSession.shared.uploadTask(with: request, from: postBody) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.resolveSuccess(call, [
                        "status": false,
                        "output": error.localizedDescription
                    ])
                    return
                }
                
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                let isSuccess = statusCode >= 200 && statusCode < 300
                
                var output: Any = [:]
                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                        output = json
                    } else if let rawString = String(data: data, encoding: .utf8) {
                        output = ["raw": rawString]
                    }
                }
                
                self?.resolveSuccess(call, [
                    "status": isSuccess,
                    "httpStatus": statusCode,
                    "output": output
                ])
            }
        }
        task.resume()
    }
    
    // MARK: - Download File
    
    @objc public func downloadFile(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        guard let path = call.getString("path"), !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resolveReject(call, "path is required")
            return
        }
        guard let fileName = call.getString("name"), !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resolveReject(call, "name is required")
            return
        }
        
        guard let url = URL(string: path) else {
            resolveReject(call, "Invalid URL")
            return
        }
        
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            resolveReject(call, "Unable to access documents directory")
            return
        }
        let destinationUrl = documentsDirectory.appendingPathComponent(fileName)
        
        let downloadId = UUID().uuidString
        let downloader = FileDownloader(plugin: self, call: call, destinationUrl: destinationUrl, downloadId: downloadId) { [weak self] id in
            self?.removeDownloader(id: id)
        }
        
        addDownloader(id: downloadId, downloader: downloader)
        downloader.start(from: url)
    }
    
    private func addDownloader(id: String, downloader: FileDownloader) {
        downloadersLock.lock()
        defer { downloadersLock.unlock() }
        activeDownloaders[id] = downloader
    }
    
    private func removeDownloader(id: String) {
        downloadersLock.lock()
        defer { downloadersLock.unlock() }
        activeDownloaders.removeValue(forKey: id)
    }
    
    // MARK: - Open File
    
    @objc public func openFile(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        guard let path = call.getString("path"), !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resolveReject(call, "path is required")
            return
        }
        
        if path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("content://") {
            resolveSuccess(call, [
                "status": false,
                "error": true,
                "message": "content:// URIs are Android-specific and not supported on iOS",
                "path": path
            ])
            return
        }
        
        guard let fileUrl = getFileUrl(path) else {
            resolveReject(call, "Invalid file path")
            return
        }
        
        if !FileManager.default.fileExists(atPath: fileUrl.path) {
            resolveSuccess(call, [
                "status": false,
                "error": true,
                "message": "File not found",
                "path": fileUrl.path
            ])
            return
        }
        
        let explicitMimeType = call.getString("type")
        let sessionId = UUID().uuidString
        
        let openerSession = FileOpenerSession(
            id: sessionId,
            plugin: self,
            call: call,
            fileUrl: fileUrl,
            mimeType: explicitMimeType
        ) { [weak self] id in
            self?.removeOpener(id: id)
        }
        
        addOpener(id: sessionId, opener: openerSession)
        openerSession.start()
    }
    
    private func addOpener(id: String, opener: FileOpenerSession) {
        openersLock.lock()
        defer { openersLock.unlock() }
        activeOpeners[id] = opener
    }
    
    private func removeOpener(id: String) {
        openersLock.lock()
        defer { openersLock.unlock() }
        activeOpeners.removeValue(forKey: id)
    }
    
    // MARK: - Resolve Native Path
    
    @objc public func resolveNativePath(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        guard let path = call.getString("path"), !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resolveReject(call, "path is required")
            return
        }
        
        if path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("content://") {
            resolveReject(call, "content:// URIs are Android-specific and not supported on iOS")
            return
        }
        
        guard let fileUrl = getFileUrl(path) else {
            resolveReject(call, "Invalid path")
            return
        }
        
        resolveSuccess(call, [
            "path": fileUrl.path
        ])
    }
    
    // MARK: - Permissions
    
    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        resolveSuccess(call, [
            "storage": "granted"
        ])
    }
    
    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        resolveSuccess(call, [
            "storage": "granted"
        ])
    }
    
    // MARK: - Bridge Helpers
    
    public func resolveSuccess(_ call: CAPPluginCall, _ data: [String: Any]) {
        DispatchQueue.main.async {
            call.resolve(data)
        }
    }
    
    public func resolveReject(_ call: CAPPluginCall, _ message: String) {
        DispatchQueue.main.async {
            call.reject(message)
        }
    }
    
    public func safeNotifyListeners(_ eventName: String, data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyListeners(eventName, data: data)
        }
    }
    
    // MARK: - View Hierarchy Helper
    
    public func getTopViewController() -> UIViewController? {
        var topController: UIViewController? = self.bridge?.viewController
        
        if topController == nil {
            if #available(iOS 13.0, *) {
                let activeScenes = UIApplication.shared.connectedScenes
                    .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
                    .compactMap { $0 as? UIWindowScene }
                for scene in activeScenes {
                    if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                        topController = keyWindow.rootViewController
                        break
                    }
                }
            }
            if topController == nil {
                topController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    ?? UIApplication.shared.windows.first?.rootViewController
            }
        }
        
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        
        if let navigationController = topController as? UINavigationController,
           let visibleController = navigationController.visibleViewController {
            topController = visibleController
        }
        
        if let tabBarController = topController as? UITabBarController,
           let selectedController = tabBarController.selectedViewController {
            topController = selectedController
        }
        
        return topController
    }
    
    // MARK: - File URL Parsing
    
    public func getFileUrl(_ path: String) -> URL? {
        var cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.isEmpty || cleanPath.hasPrefix("content://") {
            return nil
        }
        
        // Remove query parameters or fragments if attached
        if let urlObj = URL(string: cleanPath), urlObj.scheme != nil {
            if let queryRange = cleanPath.range(of: "?") {
                cleanPath = String(cleanPath[..<queryRange.lowerBound])
            }
            if let fragmentRange = cleanPath.range(of: "#") {
                cleanPath = String(cleanPath[..<fragmentRange.lowerBound])
            }
        }
        
        // Handle Capacitor WebView file URLs (e.g. capacitor://localhost/_capacitor_file_/var/...)
        if cleanPath.contains("_capacitor_file_") {
            if let range = cleanPath.range(of: "_capacitor_file_") {
                let subPath = String(cleanPath[range.upperBound...])
                let decoded = subPath.removingPercentEncoding ?? subPath
                return URL(fileURLWithPath: decoded)
            }
        }
        
        if cleanPath.hasPrefix("capacitor://") {
            let pathWithoutScheme = cleanPath.replacingOccurrences(of: "capacitor://", with: "")
            let subPath: String
            if let firstSlash = pathWithoutScheme.firstIndex(of: "/") {
                subPath = String(pathWithoutScheme[firstSlash...])
            } else {
                subPath = "/" + pathWithoutScheme
            }
            let decoded = subPath.removingPercentEncoding ?? subPath
            return URL(fileURLWithPath: decoded)
        }
        
        if cleanPath.hasPrefix("file://") {
            if let url = URL(string: cleanPath), !url.path.isEmpty {
                return URL(fileURLWithPath: url.path)
            }
            let pathWithoutScheme = cleanPath.replacingOccurrences(of: "file://", with: "")
            let decoded = pathWithoutScheme.removingPercentEncoding ?? pathWithoutScheme
            return URL(fileURLWithPath: decoded)
        }
        
        let decoded = cleanPath.removingPercentEncoding ?? cleanPath
        return URL(fileURLWithPath: decoded)
    }
    
    // MARK: - MIME & UTI Detection
    
    public func getMimeType(from url: URL) -> String {
        let pathExtension = url.pathExtension
        if pathExtension.isEmpty {
            return "application/octet-stream"
        }
        
        if #available(iOS 14.0, *) {
            if let type = UTType(filenameExtension: pathExtension),
               let mime = type.preferredMIMEType {
                return mime
            }
        }
        
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)?.takeRetainedValue() {
            if let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() as String? {
                return mime
            }
        }
        
        return "application/octet-stream"
    }
    
    public func getUTI(mimeType: String?, fileUrl: URL) -> String? {
        if let mime = mimeType, !mime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if #available(iOS 14.0, *) {
                if let type = UTType(mimeType: mime) {
                    return type.identifier
                }
            }
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mime as CFString, nil)?.takeRetainedValue() {
                return uti as String
            }
        }
        
        let ext = fileUrl.pathExtension
        if !ext.isEmpty {
            if #available(iOS 14.0, *) {
                if let type = UTType(filenameExtension: ext) {
                    return type.identifier
                }
            }
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
                return uti as String
            }
        }
        
        return nil
    }
    
    // MARK: - Multipart Construction
    
    private func sanitizeHeaderValue(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
    
    private func serializeFormValue(_ value: Any) -> String {
        if let str = value as? String {
            return str
        }
        if let boolVal = value as? Bool {
            return boolVal ? "true" : "false"
        }
        if let numVal = value as? NSNumber {
            return numVal.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let jsonData = try? JSONSerialization.data(withJSONObject: value, options: []),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            return jsonStr
        }
        return "\(value)"
    }
    
    private func createMultipartBody(
        parameters: [String: Any]?,
        boundary: String,
        files: [(key: String, fileName: String, fileUrl: URL, mimeType: String)]
    ) throws -> Data {
        var body = Data()
        
        // 1. Parameters
        if let parameters = parameters {
            for (key, value) in parameters {
                let sanitizedKey = sanitizeHeaderValue(key)
                let stringValue = serializeFormValue(value)
                
                body.safeAppend("--\(boundary)\r\n")
                body.safeAppend("Content-Disposition: form-data; name=\"\(sanitizedKey)\"\r\n\r\n")
                body.safeAppend("\(stringValue)\r\n")
            }
        }
        
        // 2. Files
        for file in files {
            let fileData = try Data(contentsOf: file.fileUrl)
            
            let sanitizedKey = sanitizeHeaderValue(file.key)
            let sanitizedFileName = sanitizeHeaderValue(file.fileName)
            let sanitizedMimeType = sanitizeHeaderValue(file.mimeType)
            
            body.safeAppend("--\(boundary)\r\n")
            body.safeAppend("Content-Disposition: form-data; name=\"\(sanitizedKey)\"; filename=\"\(sanitizedFileName)\"\r\n")
            body.safeAppend("Content-Type: \(sanitizedMimeType)\r\n\r\n")
            body.append(fileData)
            body.safeAppend("\r\n")
        }
        
        body.safeAppend("--\(boundary)--\r\n")
        
        return body
    }
}

// MARK: - Safe Data Append Extension

private extension Data {
    mutating func safeAppend(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}

// MARK: - File Downloader

class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private weak var plugin: FileUploaderPlugin?
    private var call: CAPPluginCall
    private var destinationUrl: URL
    private var downloadId: String
    private var session: URLSession?
    private var completion: (String) -> Void
    
    private var isResolved = false
    private let stateLock = NSLock()
    
    init(plugin: FileUploaderPlugin, call: CAPPluginCall, destinationUrl: URL, downloadId: String, completion: @escaping (String) -> Void) {
        self.plugin = plugin
        self.call = call
        self.destinationUrl = destinationUrl
        self.downloadId = downloadId
        self.completion = completion
        super.init()
    }
    
    func start(from url: URL) {
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        plugin?.safeNotifyListeners("downloadStatus", data: [
            "path": destinationUrl.absoluteString,
            "start": true,
            "finish": false,
            "error": false
        ])
        
        let task = session?.downloadTask(with: url)
        task?.resume()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        plugin?.safeNotifyListeners("downloadStatus", data: [
            "path": destinationUrl.absoluteString,
            "start": false,
            "finish": false,
            "error": false,
            "bytesDownloaded": totalBytesWritten,
            "totalBytes": totalBytesExpectedToWrite
        ])
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode < 200 || statusCode >= 300 {
                failOnce(with: "HTTP download failed with status code: \(statusCode)")
                cleanup()
                return
            }
        }
        
        let fileManager = FileManager.default
        let directory = destinationUrl.deletingLastPathComponent()
        
        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
            
            if fileManager.fileExists(atPath: destinationUrl.path) {
                // Atomic replace
                _ = try fileManager.replaceItemAt(destinationUrl, withItemAt: location, backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: location, to: destinationUrl)
            }
            
            plugin?.safeNotifyListeners("downloadStatus", data: [
                "path": destinationUrl.absoluteString,
                "start": false,
                "finish": true,
                "error": false
            ])
            
            resolveOnce([
                "path": destinationUrl.absoluteString,
                "status": true,
                "error": false
            ])
        } catch {
            failOnce(with: "Failed to save downloaded file: \(error.localizedDescription)")
        }
        
        cleanup()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // If already resolved (e.g. from didFinishDownloadingTo), ignore cancellation error triggered by session invalidation
            stateLock.lock()
            let alreadyDone = isResolved
            stateLock.unlock()
            
            if !alreadyDone {
                failOnce(with: error.localizedDescription)
            }
        }
        cleanup()
    }
    
    private func resolveOnce(_ result: [String: Any]) {
        stateLock.lock()
        guard !isResolved else {
            stateLock.unlock()
            return
        }
        isResolved = true
        stateLock.unlock()
        
        plugin?.resolveSuccess(call, result)
    }
    
    private func failOnce(with message: String) {
        stateLock.lock()
        guard !isResolved else {
            stateLock.unlock()
            return
        }
        isResolved = true
        stateLock.unlock()
        
        plugin?.safeNotifyListeners("downloadStatus", data: [
            "path": destinationUrl.absoluteString,
            "start": false,
            "finish": false,
            "error": true,
            "message": message
        ])
        
        plugin?.resolveSuccess(call, [
            "path": destinationUrl.absoluteString,
            "status": false,
            "error": true,
            "message": message
        ])
    }
    
    private func cleanup() {
        session?.finishTasksAndInvalidate()
        session = nil
        completion(downloadId)
    }
}

// MARK: - File Opener Session

class FileOpenerSession: NSObject, UIDocumentInteractionControllerDelegate {
    private let sessionId: String
    private weak var plugin: FileUploaderPlugin?
    private var call: CAPPluginCall
    private var fileUrl: URL
    private var mimeType: String?
    private var completion: (String) -> Void
    
    private var documentInteractionController: UIDocumentInteractionController?
    private var isResolved = false
    private let stateLock = NSLock()
    
    init(
        id: String,
        plugin: FileUploaderPlugin,
        call: CAPPluginCall,
        fileUrl: URL,
        mimeType: String?,
        completion: @escaping (String) -> Void
    ) {
        self.sessionId = id
        self.plugin = plugin
        self.call = call
        self.fileUrl = fileUrl
        self.mimeType = mimeType
        self.completion = completion
        super.init()
    }
    
    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard let viewController = self.plugin?.getTopViewController() else {
                self.fail(with: "Unable to get active view controller")
                self.finish()
                return
            }
            
            let controller = UIDocumentInteractionController(url: self.fileUrl)
            controller.delegate = self
            
            if let uti = self.plugin?.getUTI(mimeType: self.mimeType, fileUrl: self.fileUrl) {
                controller.uti = uti
            }
            
            self.documentInteractionController = controller
            
            let previewPresented = controller.presentPreview(animated: true)
            if previewPresented {
                self.resolve([
                    "status": true,
                    "error": false,
                    "path": self.fileUrl.path
                ])
                return
            }
            
            // If direct preview is not supported, present options menu
            let popoverRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            
            let menuOpened = controller.presentOptionsMenu(
                from: popoverRect,
                in: viewController.view,
                animated: true
            )
            
            if !menuOpened {
                let openInOpened = controller.presentOpenInMenu(
                    from: popoverRect,
                    in: viewController.view,
                    animated: true
                )
                
                if !openInOpened {
                    self.fail(with: "No app found to open this file")
                    self.finish()
                    return
                }
            }
            
            self.resolve([
                "status": true,
                "error": false,
                "path": self.fileUrl.path
            ])
        }
    }
    
    // MARK: - UIDocumentInteractionControllerDelegate
    
    public func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return plugin?.getTopViewController() ?? UIViewController()
    }
    
    public func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        finish()
    }
    
    public func documentInteractionControllerDidDismissOptionsMenu(_ controller: UIDocumentInteractionController) {
        finish()
    }
    
    public func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        finish()
    }
    
    // MARK: - Helpers
    
    private func resolve(_ data: [String: Any]) {
        stateLock.lock()
        guard !isResolved else {
            stateLock.unlock()
            return
        }
        isResolved = true
        stateLock.unlock()
        
        plugin?.resolveSuccess(call, data)
    }
    
    private func fail(with message: String) {
        stateLock.lock()
        guard !isResolved else {
            stateLock.unlock()
            return
        }
        isResolved = true
        stateLock.unlock()
        
        plugin?.resolveSuccess(call, [
            "status": false,
            "error": true,
            "message": message,
            "path": fileUrl.path
        ])
    }
    
    private func finish() {
        documentInteractionController = nil
        completion(sessionId)
    }
}
