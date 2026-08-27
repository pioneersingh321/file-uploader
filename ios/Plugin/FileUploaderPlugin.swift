import Foundation
import Capacitor
import UniformTypeIdentifiers

@objc(FileUploaderPlugin)
public class FileUploaderPlugin: CAPPlugin, UIDocumentInteractionControllerDelegate {
    
    private var activeDownloaders: [String: FileDownloader] = [:]
    private var documentInteractionController: UIDocumentInteractionController?
    
    @objc public func uploadFiles(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url") else {
            call.reject("url is required")
            return
        }
        guard let filesArray = call.getArray("files") else {
            call.reject("files is required and cannot be empty")
            return
        }
        
        let token = call.getString("token") ?? ""
        let fileKey = call.getString("fileKey") ?? "files[]"
        let data = call.getObject("data")
        
        guard let targetUrl = URL(string: urlString) else {
            call.reject("Invalid URL")
            return
        }
        
        var filesToUpload: [(key: String, fileName: String, fileUrl: URL, mimeType: String)] = []
        
        for item in filesArray {
            guard let fileItem = item as? [String: Any],
                  let filePath = fileItem["path"] as? String else {
                continue
            }
            
            guard let fileUrl = getFileUrl(filePath) else {
                continue
            }
            
            if !FileManager.default.fileExists(atPath: fileUrl.path) {
                continue
            }
            
            let fileName = fileUrl.lastPathComponent
            let mimeType = getMimeType(from: fileUrl)
            
            filesToUpload.append((key: fileKey, fileName: fileName, fileUrl: fileUrl, mimeType: mimeType))
        }
        
        if filesToUpload.isEmpty {
            call.reject("No valid files to upload found")
            return
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: targetUrl)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let postBody = createMultipartBody(parameters: data, boundary: boundary, files: filesToUpload)
        
        let task = URLSession.shared.uploadTask(with: request, from: postBody) { data, response, error in
            if let error = error {
                call.resolve([
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
            
            call.resolve([
                "status": isSuccess,
                "httpStatus": statusCode,
                "output": output
            ])
        }
        task.resume()
    }
    
    @objc public func uploadFile(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url") else {
            call.reject("url is required")
            return
        }
        guard let file = call.getString("file") else {
            call.reject("file is required")
            return
        }
        
        let token = call.getString("token") ?? ""
        let fileKey = call.getString("fileKey") ?? "file"
        let data = call.getObject("data")
        
        guard let targetUrl = URL(string: urlString) else {
            call.reject("Invalid URL")
            return
        }
        
        guard let fileUrl = getFileUrl(file) else {
            call.reject("Invalid file path")
            return
        }
        
        if !FileManager.default.fileExists(atPath: fileUrl.path) {
            call.reject("File does not exist: \(fileUrl.path)")
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
        
        let postBody = createMultipartBody(parameters: data, boundary: boundary, files: files)
        
        let task = URLSession.shared.uploadTask(with: request, from: postBody) { data, response, error in
            if let error = error {
                call.resolve([
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
            
            call.resolve([
                "status": isSuccess,
                "httpStatus": statusCode,
                "output": output
            ])
        }
        task.resume()
    }
    
    @objc public func downloadFile(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("path is required")
            return
        }
        guard let fileName = call.getString("name") else {
            call.reject("name is required")
            return
        }
        
        guard let url = URL(string: path) else {
            call.reject("Invalid URL")
            return
        }
        
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            call.reject("Unable to access documents directory")
            return
        }
        let destinationUrl = documentsDirectory.appendingPathComponent(fileName)
        
        let downloadId = UUID().uuidString
        let downloader = FileDownloader(plugin: self, call: call, destinationUrl: destinationUrl, downloadId: downloadId) { [weak self] id in
            self?.activeDownloaders.removeValue(forKey: id)
        }
        
        activeDownloaders[downloadId] = downloader
        downloader.start(from: url)
    }
    
    @objc public func openFile(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("path is required")
            return
        }
        
        if path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("content://") {
            call.resolve([
                "status": false,
                "error": true,
                "message": "content:// URIs are Android-specific and not supported on iOS",
                "path": path
            ])
            return
        }
        
        guard let fileUrl = getFileUrl(path) else {
            call.reject("Invalid file path")
            return
        }
        
        if !FileManager.default.fileExists(atPath: fileUrl.path) {
            call.resolve([
                "status": false,
                "error": true,
                "message": "File not found",
                "path": fileUrl.path
            ])
            return
        }
        
        DispatchQueue.main.async {
            guard let viewController = self.getTopViewController() else {
                call.reject("Unable to get active view controller")
                return
            }
            
            self.documentInteractionController = UIDocumentInteractionController(url: fileUrl)
            self.documentInteractionController?.delegate = self
            
            let presented = self.documentInteractionController?.presentPreview(animated: true) ?? false
            if !presented {
                let opened = self.documentInteractionController?.presentOptionsMenu(
                    from: viewController.view.bounds,
                    in: viewController.view,
                    animated: true
                ) ?? false
                
                if !opened {
                    call.resolve([
                        "status": false,
                        "error": true,
                        "message": "No app found to open this file",
                        "path": fileUrl.path
                    ])
                    return
                }
            }
            
            call.resolve([
                "status": true,
                "error": false,
                "path": fileUrl.path
            ])
        }
    }
    
    @objc public func resolveNativePath(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("path is required")
            return
        }
        
        if path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("content://") {
            call.reject("content:// URIs are Android-specific and not supported on iOS")
            return
        }
        
        guard let fileUrl = getFileUrl(path) else {
            call.reject("Invalid path")
            return
        }
        
        call.resolve([
            "path": fileUrl.path
        ])
    }
    
    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve([
            "storage": "granted"
        ])
    }
    
    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        call.resolve([
            "storage": "granted"
        ])
    }
    
    // MARK: - UIDocumentInteractionControllerDelegate
    
    public func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self.getTopViewController() ?? UIViewController()
    }
    
    public func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        self.documentInteractionController = nil
    }
    
    // MARK: - Helpers
    
    private func getTopViewController() -> UIViewController? {
        var topController = self.bridge?.viewController ?? self.viewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
    }
    
    private func getFileUrl(_ path: String) -> URL? {
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPath.isEmpty || cleanPath.hasPrefix("content://") {
            return nil
        }
        
        // Handle Capacitor WebView file URLs (e.g. capacitor://localhost/_capacitor_file_/var/...)
        if cleanPath.contains("_capacitor_file_") {
            if let range = cleanPath.range(of: "_capacitor_file_") {
                let subPath = String(cleanPath[range.upperBound...])
                let decoded = subPath.removingPercentEncoding ?? subPath
                return URL(fileURLWithPath: decoded)
            }
        }
        
        if cleanPath.hasPrefix("file://") {
            if let url = URL(string: cleanPath) {
                return url
            }
            let pathWithoutScheme = cleanPath.replacingOccurrences(of: "file://", with: "")
            let decoded = pathWithoutScheme.removingPercentEncoding ?? pathWithoutScheme
            return URL(fileURLWithPath: decoded)
        }
        
        let decoded = cleanPath.removingPercentEncoding ?? cleanPath
        return URL(fileURLWithPath: decoded)
    }
    
    private func getMimeType(from url: URL) -> String {
        let pathExtension = url.pathExtension
        if let type = UTType(filenameExtension: pathExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
    
    private func createMultipartBody(
        parameters: [String: Any]?,
        boundary: String,
        files: [(key: String, fileName: String, fileUrl: URL, mimeType: String)]
    ) -> Data {
        var body = Data()
        
        if let parameters = parameters {
            for (key, value) in parameters {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
        }
        
        for file in files {
            guard let fileData = try? Data(contentsOf: file.fileUrl) else {
                continue
            }
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(file.key)\"; filename=\"\(file.fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    private func isBlank(_ value: String?) -> Bool {
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}

class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private var plugin: CAPPlugin
    private var call: CAPPluginCall
    private var destinationUrl: URL
    private var session: URLSession?
    private var completion: (String) -> Void
    private var downloadId: String
    
    init(plugin: CAPPlugin, call: CAPPluginCall, destinationUrl: URL, downloadId: String, completion: @escaping (String) -> Void) {
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
        
        plugin.notifyListeners("downloadStatus", data: [
            "path": destinationUrl.absoluteString,
            "start": true,
            "finish": false,
            "error": false
        ])
        
        let task = session?.downloadTask(with: url)
        task?.resume()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        plugin.notifyListeners("downloadStatus", data: [
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
                fail(with: "HTTP download failed with status code: \(statusCode)")
                session.invalidateAndCancel()
                completion(downloadId)
                return
            }
        }
        
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destinationUrl.path) {
                try fileManager.removeItem(at: destinationUrl)
            }
            try fileManager.moveItem(at: location, to: destinationUrl)
            
            plugin.notifyListeners("downloadStatus", data: [
                "path": destinationUrl.absoluteString,
                "start": false,
                "finish": true,
                "error": false
            ])
            
            call.resolve([
                "path": destinationUrl.absoluteString,
                "status": true,
                "error": false
            ])
        } catch {
            fail(with: error.localizedDescription)
        }
        session.invalidateAndCancel()
        completion(downloadId)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            fail(with: error.localizedDescription)
        }
        session.invalidateAndCancel()
        completion(downloadId)
    }
    
    private func fail(with message: String) {
        plugin.notifyListeners("downloadStatus", data: [
            "path": destinationUrl.absoluteString,
            "start": false,
            "finish": false,
            "error": true,
            "message": message
        ])
        
        call.resolve([
            "path": destinationUrl.absoluteString,
            "status": false,
            "error": true,
            "message": message
        ])
    }
}
