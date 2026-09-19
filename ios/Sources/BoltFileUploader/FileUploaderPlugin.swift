import Foundation
import Capacitor
import UIKit
import UniformTypeIdentifiers
import MobileCoreServices
import os.log

// MARK: - TypeLogger

/// Structured OSLog-based logger for tracing data types at every bridge boundary.
/// Use this to diagnose type coercion issues across iOS versions and device models.
internal enum TypeLogger {
    // Subsystem matches the bundle identifier pattern for easy Console.app filtering.
    private static let subsystem = "bolt.fileuploader"

    static let upload   = OSLog(subsystem: subsystem, category: "upload")
    static let download = OSLog(subsystem: subsystem, category: "download")
    static let open     = OSLog(subsystem: subsystem, category: "open")
    static let bridge   = OSLog(subsystem: subsystem, category: "bridge")
    static let typecheck = OSLog(subsystem: subsystem, category: "typecheck")

    /// Log a data-boundary trace: records the value's Swift dynamic type alongside
    /// a human-readable label so engineers can track exactly where a type changes.
    static func trace(_ label: String, value: Any, log: OSLog = TypeLogger.bridge) {
        let typeName = String(describing: type(of: value))
        os_log("[TypeTrace] %{public}@ → type=%{public}@", log: log, type: .debug, label, typeName)
    }

    /// Log a type mismatch warning that will appear in Console.app at Warning level.
    static func warn(_ message: String, log: OSLog = TypeLogger.typecheck) {
        os_log("[TypeWarn] %{public}@", log: log, type: .error, message)
    }

    /// Log a type validation failure (unserializable value detected in a bridge payload).
    static func typeError(_ key: String, value: Any, log: OSLog = TypeLogger.typecheck) {
        let typeName = String(describing: type(of: value))
        os_log(
            "[TypeError] Non-serializable value at key '%{public}@': type=%{public}@, value=%{public}@",
            log: log,
            type: .fault,
            key, typeName, "\(value)"
        )
    }
}

// MARK: - BridgePayloadValidator

/// Validates that every value in a dictionary destined for `call.resolve()` is
/// JSON-serializable. Logs structured warnings for any value that would be silently
/// dropped or coerced by `JSONSerialization` or the Capacitor JS bridge.
internal enum BridgePayloadValidator {

    /// Set of Swift types that the Capacitor bridge can round-trip cleanly.
    private static func isSerializable(_ value: Any) -> Bool {
        switch value {
        case is String, is Bool, is Int, is Int32, is Int64,
             is UInt, is UInt32, is UInt64, is Double, is Float,
             is NSNumber, is NSNull:
            return true
        case let dict as [String: Any]:
            return dict.values.allSatisfy { isSerializable($0) }
        case let arr as [Any]:
            return arr.allSatisfy { isSerializable($0) }
        default:
            return false
        }
    }

    /// Validate every top-level key/value pair and log any violations.
    /// Returns `true` if the payload is fully clean, `false` otherwise.
    @discardableResult
    static func validate(_ payload: [String: Any], context: String) -> Bool {
        var isClean = true
        for (key, value) in payload {
            TypeLogger.trace("\(context).\(key)", value: value)
            if !isSerializable(value) {
                TypeLogger.typeError(key, value: value)
                isClean = false
            }
        }
        return isClean
    }
}

// MARK: - FileUploaderPlugin

@objc(FileUploaderPlugin)
public class FileUploaderPlugin: CAPPlugin {
    
    private var activeDownloaders: [String: FileDownloader] = [:]
    private let downloadersLock = NSLock()
    
    private var activeOpeners: [String: FileOpenerSession] = [:]
    private let openersLock = NSLock()
    
    // MARK: - Upload Files
    
    @objc public func uploadFiles(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        os_log("[upload] uploadFiles called", log: TypeLogger.upload, type: .info)
        
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
        
        // Log incoming data field types for diagnostics
        if let data = data {
            os_log("[upload] data fields received: %{public}@",
                   log: TypeLogger.upload, type: .debug,
                   data.keys.joined(separator: ", "))
            for (k, v) in data {
                TypeLogger.trace("uploadFiles.data.\(k)", value: v, log: TypeLogger.upload)
            }
        }
        
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
            
            // Log the raw type of the path value arriving from the bridge
            TypeLogger.trace("uploadFiles.files[\(index)].path", value: filePath, log: TypeLogger.upload)
            
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
            
            os_log("[upload] Prepared file[%d]: name=%{public}@, mime=%{public}@",
                   log: TypeLogger.upload, type: .debug, index, fileName, mimeType)
            
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
        os_log("[upload] uploadFiles: sending %d bytes to %{public}@",
               log: TypeLogger.upload, type: .info, postBody.count, urlString)
        
        let task = URLSession.shared.uploadTask(with: request, from: postBody) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    os_log("[upload] uploadFiles network error: %{public}@",
                           log: TypeLogger.upload, type: .error, error.localizedDescription)
                    self?.resolveSuccess(call, [
                        "status": false,
                        "output": error.localizedDescription
                    ])
                    return
                }
                
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                let isSuccess = statusCode >= 200 && statusCode < 300
                
                os_log("[upload] uploadFiles response: httpStatus=%d, success=%{public}@",
                       log: TypeLogger.upload, type: .info, statusCode, isSuccess ? "true" : "false")
                
                // Build output — handles top-level objects AND top-level arrays safely.
                let output = self?.parseResponseData(data, context: "uploadFiles") ?? [String: Any]()
                
                let payload: [String: Any] = [
                    "status": isSuccess,
                    "httpStatus": statusCode,
                    "output": output
                ]
                BridgePayloadValidator.validate(payload, context: "uploadFiles.resolve")
                self?.resolveSuccess(call, payload)
            }
        }
        task.resume()
    }
    
    // MARK: - Upload File
    
    @objc public func uploadFile(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        os_log("[upload] uploadFile called", log: TypeLogger.upload, type: .info)
        
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
        
        // Log incoming data field types
        if let data = data {
            for (k, v) in data {
                TypeLogger.trace("uploadFile.data.\(k)", value: v, log: TypeLogger.upload)
            }
        }
        
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
        
        os_log("[upload] uploadFile: name=%{public}@, mime=%{public}@",
               log: TypeLogger.upload, type: .debug, fileName, mimeType)
        
        let files = [(key: fileKey, fileName: fileName, fileUrl: fileUrl, mimeType: mimeType)]
        
        let postBody: Data
        do {
            postBody = try createMultipartBody(parameters: data, boundary: boundary, files: files)
        } catch {
            resolveReject(call, "Failed to create multipart request: \(error.localizedDescription)")
            return
        }
        
        request.setValue("\(postBody.count)", forHTTPHeaderField: "Content-Length")
        os_log("[upload] uploadFile: sending %d bytes to %{public}@",
               log: TypeLogger.upload, type: .info, postBody.count, urlString)
        
        let task = URLSession.shared.uploadTask(with: request, from: postBody) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    os_log("[upload] uploadFile network error: %{public}@",
                           log: TypeLogger.upload, type: .error, error.localizedDescription)
                    self?.resolveSuccess(call, [
                        "status": false,
                        "output": error.localizedDescription
                    ])
                    return
                }
                
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                let isSuccess = statusCode >= 200 && statusCode < 300
                
                os_log("[upload] uploadFile response: httpStatus=%d, success=%{public}@",
                       log: TypeLogger.upload, type: .info, statusCode, isSuccess ? "true" : "false")
                
                let output = self?.parseResponseData(data, context: "uploadFile") ?? [String: Any]()
                
                let payload: [String: Any] = [
                    "status": isSuccess,
                    "httpStatus": statusCode,
                    "output": output
                ]
                BridgePayloadValidator.validate(payload, context: "uploadFile.resolve")
                self?.resolveSuccess(call, payload)
            }
        }
        task.resume()
    }
    
    // MARK: - Download File
    
    @objc public func downloadFile(_ call: CAPPluginCall) {
        call.keepAlive = true
        
        os_log("[download] downloadFile called", log: TypeLogger.download, type: .info)
        
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
        
        os_log("[download] destinationUrl=%{public}@", log: TypeLogger.download, type: .debug,
               destinationUrl.absoluteString)
        
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
        
        os_log("[open] openFile called", log: TypeLogger.open, type: .info)
        
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
                // FIX: Always percent-decode before constructing a file URL.
                let decoded = subPath.removingPercentEncoding ?? subPath
                TypeLogger.trace("getFileUrl._capacitor_file_", value: decoded, log: TypeLogger.bridge)
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
            // FIX: Always percent-decode before constructing a file URL.
            let decoded = subPath.removingPercentEncoding ?? subPath
            TypeLogger.trace("getFileUrl.capacitor://", value: decoded, log: TypeLogger.bridge)
            return URL(fileURLWithPath: decoded)
        }
        
        if cleanPath.hasPrefix("file://") {
            // Preferred path: use URL(string:) which correctly handles percent-encoded chars.
            if let url = URL(string: cleanPath), !url.path.isEmpty {
                // url.path already percent-decodes the path component.
                TypeLogger.trace("getFileUrl.file://(parsed)", value: url.path, log: TypeLogger.bridge)
                return URL(fileURLWithPath: url.path)
            }
            // FIX: Fallback — strip scheme then ALWAYS percent-decode before fileURLWithPath.
            // On iOS 16+, URL(fileURLWithPath:) with encoded characters fails silently.
            let pathWithoutScheme = cleanPath.replacingOccurrences(of: "file://", with: "")
            let decoded = pathWithoutScheme.removingPercentEncoding ?? pathWithoutScheme
            TypeLogger.trace("getFileUrl.file://(fallback)", value: decoded, log: TypeLogger.bridge)
            return URL(fileURLWithPath: decoded)
        }
        
        // Plain POSIX path — percent-decode in case it arrived from a web context.
        let decoded = cleanPath.removingPercentEncoding ?? cleanPath
        TypeLogger.trace("getFileUrl.posix", value: decoded, log: TypeLogger.bridge)
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
    
    // MARK: - Response Parsing
    
    /// Parse raw HTTP response data into a bridge-safe `[String: Any]`.
    ///
    /// Handles three cases:
    /// 1. Valid JSON **object** → returned as-is.
    /// 2. Valid JSON **array** → wrapped in `{"items": [...]}` so the Capacitor bridge
    ///    always receives an object (top-level arrays were previously silently dropped on iOS).
    /// 3. Non-JSON text → returned as `{"raw": "<string>"}`.
    ///
    /// This normalizes behavior across all iOS versions and matches Android's output shape.
    internal func parseResponseData(_ data: Data?, context: String) -> [String: Any] {
        guard let data = data, !data.isEmpty else {
            os_log("[bridge] %{public}@: no response data", log: TypeLogger.bridge, type: .debug, context)
            return [:]
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            TypeLogger.trace("\(context).responseJSON", value: json, log: TypeLogger.bridge)
            
            if let dict = json as? [String: Any] {
                // Case 1: Top-level JSON object — ideal, return directly.
                os_log("[bridge] %{public}@: parsed as JSON object", log: TypeLogger.bridge, type: .debug, context)
                return dict
            } else if let arr = json as? [Any] {
                // Case 2: Top-level JSON array — wrap it so the bridge always emits an object.
                // Previously this caused `output` to remain `[:]` on iOS, losing all data.
                os_log("[bridge] %{public}@: parsed as JSON array (wrapping in items key)",
                       log: TypeLogger.bridge, type: .info, context)
                TypeLogger.warn("\(context): server returned a top-level JSON array. Wrapping as {\"items\":[…]}. Consider updating the API to return an object.")
                return ["items": arr]
            } else {
                // Scalar JSON value (number, string, bool) — wrap it.
                let typeName = String(describing: type(of: json))
                os_log("[bridge] %{public}@: parsed as scalar JSON (%{public}@), wrapping as value",
                       log: TypeLogger.bridge, type: .info, context, typeName)
                return ["value": json]
            }
        }
        
        // Case 3: Not valid JSON — return raw string.
        if let rawString = String(data: data, encoding: .utf8) {
            os_log("[bridge] %{public}@: non-JSON response, returning as raw string",
                   log: TypeLogger.bridge, type: .info, context)
            return ["raw": rawString]
        }
        
        os_log("[bridge] %{public}@: unreadable response data", log: TypeLogger.bridge, type: .error, context)
        return [:]
    }
    
    // MARK: - Multipart Construction
    
    private func sanitizeHeaderValue(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
    
    /// Serialize a form field value to its string representation.
    ///
    /// **Type disambiguation note (iOS-specific):**
    /// On iOS, JavaScript `true`/`false` values arrive from the Capacitor bridge as
    /// `__NSCFBoolean` (an `NSNumber` subclass tagged with `kCFBooleanTrue/False`).
    /// Checking `value is Bool` alone is insufficient because `NSNumber` also conforms
    /// to `Bool` in certain Swift contexts. We use `CFGetTypeID` for reliable detection.
    private func serializeFormValue(_ value: Any) -> String {
        // FIX: Use Core Foundation type ID to reliably distinguish booleans from
        // numeric NSNumbers before falling through to the NSNumber branch.
        // This prevents iOS from serializing `true` as "1" and `false` as "0".
        if let nsNum = value as? NSNumber {
            let boolTypeID = CFBooleanGetTypeID()
            if CFGetTypeID(nsNum) == boolTypeID {
                let boolVal = nsNum.boolValue
                let serialized = boolVal ? "true" : "false"
                TypeLogger.trace("serializeFormValue.bool(\(serialized))", value: value, log: TypeLogger.typecheck)
                return serialized
            }
            // Genuine numeric NSNumber
            TypeLogger.trace("serializeFormValue.number(\(nsNum.stringValue))", value: value, log: TypeLogger.typecheck)
            return nsNum.stringValue
        }
        if let str = value as? String {
            TypeLogger.trace("serializeFormValue.string", value: value, log: TypeLogger.typecheck)
            return str
        }
        if JSONSerialization.isValidJSONObject(value),
           let jsonData = try? JSONSerialization.data(withJSONObject: value, options: []),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            TypeLogger.trace("serializeFormValue.json", value: value, log: TypeLogger.typecheck)
            return jsonStr
        }
        TypeLogger.warn("serializeFormValue: falling back to string interpolation for type \(type(of: value))")
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
                
                os_log("[upload] form-data field: key=%{public}@, valueType=%{public}@",
                       log: TypeLogger.upload, type: .debug,
                       key, String(describing: type(of: value)))
                
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
            
            os_log("[upload] form-data file: key=%{public}@, name=%{public}@, mime=%{public}@, bytes=%d",
                   log: TypeLogger.upload, type: .debug,
                   sanitizedKey, sanitizedFileName, sanitizedMimeType, fileData.count)
            
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

// MARK: - Progress Value Safety

/// Safely converts an `Int64` byte-count value for the Capacitor JS bridge.
///
/// JavaScript's `Number` type is IEEE-754 double-precision, which can represent
/// integers exactly only up to 2^53 (Number.MAX_SAFE_INTEGER = 9,007,199,254,740,991).
/// Files larger than ~8 PiB would overflow; we clamp and log if that occurs.
private func safeProgressValue(_ value: Int64, label: String) -> NSNumber {
    let maxSafe: Int64 = 9_007_199_254_740_991
    if value > maxSafe {
        TypeLogger.warn("Progress value '\(label)'=\(value) exceeds JS Number.MAX_SAFE_INTEGER (\(maxSafe)). Clamping to avoid precision loss.")
        return NSNumber(value: maxSafe)
    }
    return NSNumber(value: value)
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
        
        os_log("[download] Starting download: url=%{public}@, destination=%{public}@",
               log: TypeLogger.download, type: .info, url.absoluteString, destinationUrl.absoluteString)
        
        // FIX: Consistently use absoluteString (file:// URI) in all download events
        // so the TypeScript consumer always receives the same path format.
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
        // FIX: Wrap Int64 values in NSNumber via safeProgressValue to prevent
        // silent precision loss when the Capacitor bridge serializes to JS Number.
        let safeWritten = safeProgressValue(totalBytesWritten, label: "bytesDownloaded")
        let safeTotal   = safeProgressValue(totalBytesExpectedToWrite, label: "totalBytes")
        
        os_log("[download] Progress: written=%lld, total=%lld",
               log: TypeLogger.download, type: .debug, totalBytesWritten, totalBytesExpectedToWrite)
        
        let payload: [String: Any] = [
            "path": destinationUrl.absoluteString,
            "start": false,
            "finish": false,
            "error": false,
            "bytesDownloaded": safeWritten,
            "totalBytes": safeTotal
        ]
        BridgePayloadValidator.validate(payload, context: "downloadStatus.progress")
        plugin?.safeNotifyListeners("downloadStatus", data: payload)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            os_log("[download] HTTP status: %d", log: TypeLogger.download, type: .info, statusCode)
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
            
            os_log("[download] File saved to %{public}@", log: TypeLogger.download, type: .info, destinationUrl.path)
            
            // FIX: Consistently use absoluteString (file:// URI) for the path value
            // in both the event and the resolve result, matching the start event format.
            let finishPayload: [String: Any] = [
                "path": destinationUrl.absoluteString,
                "start": false,
                "finish": true,
                "error": false
            ]
            BridgePayloadValidator.validate(finishPayload, context: "downloadStatus.finish")
            plugin?.safeNotifyListeners("downloadStatus", data: finishPayload)
            
            let resolvePayload: [String: Any] = [
                "path": destinationUrl.absoluteString,
                "status": true,
                "error": false
            ]
            BridgePayloadValidator.validate(resolvePayload, context: "downloadFile.resolve")
            resolveOnce(resolvePayload)
        } catch {
            TypeLogger.warn("Download file save failed: \(error.localizedDescription)")
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
                os_log("[download] Task error: %{public}@", log: TypeLogger.download, type: .error, error.localizedDescription)
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
        
        let eventPayload: [String: Any] = [
            "path": destinationUrl.absoluteString,
            "start": false,
            "finish": false,
            "error": true,
            "message": message
        ]
        BridgePayloadValidator.validate(eventPayload, context: "downloadStatus.error")
        plugin?.safeNotifyListeners("downloadStatus", data: eventPayload)
        
        let resolvePayload: [String: Any] = [
            "path": destinationUrl.absoluteString,
            "status": false,
            "error": true,
            "message": message
        ]
        BridgePayloadValidator.validate(resolvePayload, context: "downloadFile.resolve.error")
        plugin?.resolveSuccess(call, resolvePayload)
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
            
            os_log("[open] Opening file: %{public}@", log: TypeLogger.open, type: .info, self.fileUrl.path)
            
            guard let viewController = self.plugin?.getTopViewController() else {
                self.fail(with: "Unable to get active view controller")
                self.finish()
                return
            }
            
            let controller = UIDocumentInteractionController(url: self.fileUrl)
            controller.delegate = self
            
            if let uti = self.plugin?.getUTI(mimeType: self.mimeType, fileUrl: self.fileUrl) {
                os_log("[open] Using UTI: %{public}@", log: TypeLogger.open, type: .debug, uti)
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
        
        BridgePayloadValidator.validate(data, context: "openFile.resolve")
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
        
        let payload: [String: Any] = [
            "status": false,
            "error": true,
            "message": message,
            "path": fileUrl.path
        ]
        BridgePayloadValidator.validate(payload, context: "openFile.resolve.error")
        plugin?.resolveSuccess(call, payload)
    }
    
    private func finish() {
        documentInteractionController = nil
        completion(sessionId)
    }
}
