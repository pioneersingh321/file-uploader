# @bolt/file-uploader

[![npm version](https://img.shields.io/npm/v/@bolt/file-uploader.svg)](https://www.npmjs.com/package/@bolt/file-uploader)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Capacitor](https://img.shields.io/badge/Capacitor-8%2B-blue.svg)](https://capacitorjs.com/)

![File Uploader Banner](assets/banner.png)

A high-performance Capacitor plugin for single & multi-file uploads, background downloads with progress events, file opening via system intents/previews, and native path resolution for Android and iOS.

## Features

- 📤 **Multipart Uploads**: Single file (`uploadFile`) or batch files (`uploadFiles`) with Bearer token authentication & custom form fields.
- 📥 **File Downloads**: Real-time progress monitoring (`downloadStatus` event listener) saved directly to public Downloads (Android) or Documents (iOS).
- 📂 **Native Path Resolution**: Resolves Android `content://` URIs and `file://` schemes into local native paths (with automatic cache fallback).
- 👁️ **File Opening**: Open downloaded files using native system applications (`FileProvider` / `Intent` on Android, `UIDocumentInteractionController` on iOS).
- 🔐 **Permission Management**: Storage permission request and check helpers built-in.
- 📱 **Cross-Platform**: Support for **Android** and **iOS** (Capacitor 8+).

---

## Requirements

- **Node.js**: 20+
- **Capacitor**: `@capacitor/core` ^8.0.0
- **Platforms**: Android (SDK 22+), iOS (14.0+)

---

## Installation

### Install via Git

```bash
npm install git+https://github.com/pioneersingh321/file-uploader.git
npx cap sync
```

Install a specific branch or release tag:

```bash
# Install specific branch
npm install git+https://github.com/pioneersingh321/file-uploader.git#main

# Install specific release tag
npm install git+https://github.com/pioneersingh321/file-uploader.git#v1.0.0
```

### Install via Private SSH

```bash
npm install git+ssh://git@github.com/pioneersingh321/file-uploader.git
npx cap sync
```

### Install from Local Path

```bash
npm install ../file-uploader
npx cap sync
```

*Note: The plugin executes `npm run build` automatically during installation (`prepare` script).*

---

## Usage Guide

Import `FileUploader` into your Capacitor TypeScript project:

```ts
import { FileUploader } from '@bolt/file-uploader';
```

### 1. Upload a Single File

```ts
import { FileUploader } from '@bolt/file-uploader';

async function handleFileUpload() {
  try {
    const result = await FileUploader.uploadFile({
      url: 'https://api.example.com/v1/upload',
      token: 'your-bearer-token',       // Optional: Sent as `Authorization: Bearer ...`
      fileKey: 'avatar',                // Optional: Multipart form field name (default: "file")
      file: 'file:///storage/emulated/0/Download/photo.jpg', // File URI or native path
      data: {
        userId: 'user_123',             // Optional: Additional form fields
        category: 'profile',
      },
    });

    if (result.status) {
      console.log('Upload success! HTTP Status:', result.httpStatus);
      console.log('Server response output:', result.output);
    } else {
      console.error('Upload failed with output:', result.output);
    }
  } catch (error) {
    console.error('Upload error:', error);
  }
}
```

### 2. Upload Multiple Files (Batch Upload)

```ts
import { FileUploader } from '@bolt/file-uploader';

async function handleBatchUpload() {
  const result = await FileUploader.uploadFiles({
    url: 'https://api.example.com/v1/upload-batch',
    token: 'your-bearer-token',
    fileKey: 'documents[]',             // Optional: Form field name for files (default: "files[]")
    files: [
      { path: '/path/to/document1.pdf' },
      { path: 'file:///path/to/document2.pdf' },
    ],
    data: {
      folderId: 'folder_99',
    },
  });

  console.log('Batch upload status:', result.status);
}
```

### 3. Resolve Native Paths (`content://` URIs)

When using an Android media picker, paths are often returned as `content://` URIs. Use `resolveNativePath` to convert them to standard file system paths prior to uploading.

```ts
import { FileUploader } from '@bolt/file-uploader';

async function getRealPath(contentUri: string) {
  const { path } = await FileUploader.resolveNativePath({
    path: contentUri, // e.g., 'content://com.android.providers.media.documents/document/image%3A123'
  });

  console.log('Resolved absolute native path:', path);
  return path;
}
```

*Note: If direct MediaStore query fails, the plugin safely streams the content into the app's cache directory and returns the cached file path.*

### 4. Download a File with Real-Time Progress

```ts
import { FileUploader } from '@bolt/file-uploader';

async function startDownload() {
  // 1. Listen for download progress updates before initiating download
  const progressListener = await FileUploader.addListener('downloadStatus', info => {
    if (info.start) {
      console.log('Download started for:', info.path);
    }
    
    if (info.bytesDownloaded !== undefined && info.totalBytes) {
      const percentage = Math.round((info.bytesDownloaded / info.totalBytes) * 100);
      console.log(`Progress: ${percentage}% (${info.bytesDownloaded}/${info.totalBytes} bytes)`);
    }
    
    if (info.finish) {
      console.log('Download completed successfully:', info.path);
    }
    
    if (info.error) {
      console.error('Download error:', info.message);
    }
  });

  // 2. Trigger file download
  const result = await FileUploader.downloadFile({
    path: 'https://example.com/files/annual-report.pdf',
    name: 'annual-report.pdf',
  });

  if (result.status) {
    console.log('File saved locally at:', result.path);
  }

  // 3. Clean up event listener when finished
  await progressListener.remove();
}
```

### 5. Open a Downloaded File

Opens the file with the operating system's native viewer (e.g. PDF reader, image viewer).

```ts
import { FileUploader } from '@bolt/file-uploader';

async function openReport(filePath: string) {
  const result = await FileUploader.openFile({
    path: filePath,                     // File path or file:// URI
    type: 'application/pdf',            // Optional: MIME type (default: application/pdf)
  });

  if (!result.status) {
    console.warn('Could not open file:', result.message);
  }
}
```

### 6. Storage Permissions

```ts
import { FileUploader } from '@bolt/file-uploader';

async function checkAndRequestPermissions() {
  let status = await FileUploader.checkPermissions();
  if (status.storage !== 'granted') {
    status = await FileUploader.requestPermissions();
  }
  console.log('Storage permission:', status.storage);
}
```

---

## API Reference

### Methods

| Method | Parameters | Returns | Description |
| :--- | :--- | :--- | :--- |
| `uploadFile(options)` | `UploadFileOptions` | `Promise<UploadResult>` | Uploads a single file using multipart HTTP POST. |
| `uploadFiles(options)` | `UploadFilesOptions` | `Promise<UploadResult>` | Uploads multiple files in a single multipart POST. |
| `downloadFile(options)` | `DownloadFileOptions` | `Promise<DownloadResult>` | Downloads a remote file to public Downloads (Android) or Documents (iOS). |
| `openFile(options)` | `OpenFileOptions` | `Promise<OpenResult>` | Opens a local file with the default system application. |
| `resolveNativePath(options)` | `ResolveNativePathOptions` | `Promise<ResolveNativePathResult>` | Resolves `content://` or `file://` URIs to native absolute file paths. |
| `checkPermissions()` | None | `Promise<PermissionStatus>` | Checks external storage permissions status. |
| `requestPermissions()` | None | `Promise<PermissionStatus>` | Requests external storage permissions from the user. |
| `addListener('downloadStatus', fn)` | Event Name, Callback | `Promise<PluginListenerHandle>` | Subscribes to download progress and completion events. |
| `removeAllListeners()` | None | `Promise<void>` | Removes all active plugin event listeners. |

---

## Type Definitions

```ts
export interface UploadFileOptions {
  url: string;                          // Destination endpoint URL
  token?: string;                       // Optional Bearer token
  data?: Record<string, unknown>;       // Optional additional form parameters
  fileKey?: string;                     // Multipart field name (default: "file")
  file: string;                         // File path or file:// URI
}

export interface UploadFilesOptions {
  url: string;                          // Destination endpoint URL
  token?: string;                       // Optional Bearer token
  data?: Record<string, unknown>;       // Optional additional form parameters
  fileKey?: string;                     // Multipart field name (default: "files[]")
  files: UploadFileItem[];              // Array of file objects
}

export interface UploadFileItem {
  path: string;                         // File path or file:// URI
}

export interface UploadResult {
  status: boolean;                      // True if HTTP status is 2xx
  httpStatus?: number;                  // HTTP Status code (e.g., 200, 400, 500)
  output: unknown;                      // Parsed JSON response body or { raw: string }
}

export interface DownloadFileOptions {
  path: string;                         // Remote file URL
  name: string;                         // Target filename to save as
}

export interface DownloadResult {
  path: string;                         // Local file path where saved
  status: boolean;                      // True if download completed successfully
  error: boolean;                       // True if an error occurred
  message?: string;                     // Error description if failed
}

export interface OpenFileOptions {
  path: string;                         // Local file path or file:// URI
  type?: string;                        // Optional MIME type (default: "application/pdf")
}

export interface OpenResult {
  path?: string;                        // File path attempted
  status: boolean;                      // True if file viewer launched successfully
  error: boolean;                       // True if failed to open
  message?: string;                     // Error message if opening failed
}

export interface ResolveNativePathOptions {
  path: string;                         // content:// or file:// URI string
}

export interface ResolveNativePathResult {
  path: string;                         // Absolute filesystem path
}

export interface DownloadStatusInfo {
  path: string;                         // Target file path
  start: boolean;                       // True when download begins
  finish: boolean;                      // True when download finishes successfully
  error: boolean;                       // True if download fails
  bytesDownloaded?: number;             // Total bytes downloaded so far
  totalBytes?: number;                  // Expected total size in bytes
  message?: string;                     // Error details if failed
}

export interface PermissionStatus {
  storage: PermissionState;             // 'prompt' | 'prompt-with-rationale' | 'granted' | 'denied'
}
```

---

## Platform Details

### Android
- **File Opening**: Utilizes Android's `FileProvider` (`${applicationId}.fileprovider`) to securely share URIs with external viewer apps via `Intent.ACTION_VIEW`.
- **Downloads Directory**: Files are downloaded directly to public `Environment.DIRECTORY_DOWNLOADS`.
- **URI Resolution**: Handles `content://` URIs by querying `MediaStore`. If access is restricted, the plugin seamlessly copies the content stream into the app's cache folder (`cacheDir`).

### iOS
- **File Storage**: Downloads are stored in the app's standard `DocumentsDirectory`.
- **File Opening**: Utilizes `UIDocumentInteractionController` to present a full preview or system "Open In" menu.
- **URI Resolution**: Automatically decodes percent-encoded `file://` paths to POSIX paths.
- **Permissions**: `checkPermissions` and `requestPermissions` return `"granted"` (as iOS manages file access via standard app sandbox scopes).

### Web
- Calling any method on Web will throw an explicit error: `FileUpload is not implemented on "<platform>"`.

---

## Development & Building

To build the plugin locally:

```bash
# Install dependencies
npm install

# Build TypeScript and bundle via Rollup
npm run build

# Watch for TypeScript changes during development
npm run watch
```

---

## License

[MIT](LICENSE) © Pioneer Singh
