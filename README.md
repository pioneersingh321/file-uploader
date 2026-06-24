# @bolt/file-uploader

Capacitor plugin for Android file upload, download, and open operations. Supports multipart uploads with auth tokens, download progress events, and resolving `content://` URIs to native paths.

**Platform support:** Android only (Capacitor 8+).

**Repository:** https://github.com/pioneersingh321/file-uploader

## Requirements

- Node.js 20+
- A Capacitor 8 app with the Android platform added
- `@capacitor/core` ^8.0.0

## Install from Git

### Option A — npm from a public GitHub repo

From your Capacitor app directory:

```bash
npm install git+https://github.com/pioneersingh321/file-uploader.git
npx cap sync android
```

Install a specific branch or tag:

```bash
npm install git+https://github.com/pioneersingh321/file-uploader.git#main
npm install git+https://github.com/pioneersingh321/file-uploader.git#v1.0.0
```

### Option B — npm from a private GitHub repo (SSH)

```bash
npm install git+ssh://git@github.com/pioneersingh321/file-uploader.git
npx cap sync android
```

### Option C — clone and link locally

```bash
git clone https://github.com/pioneersingh321/file-uploader.git
cd your-capacitor-app
npm install ../file-uploader
npx cap sync android
```

### Option D — install from a local folder (no Git remote)

```bash
npm install ../file-uploader
npx cap sync android
```

The plugin runs `npm run build` automatically during install (`prepare` script), so `dist/` does not need to be committed.

## Usage

Import the plugin in your app:

```ts
import { FileUploader } from '@bolt/file-uploader';
```

### Upload a single file

```ts
const result = await FileUploader.uploadFile({
  url: 'https://api.example.com/upload',
  token: 'your-bearer-token',       // optional; sent as Authorization: Bearer ...
  fileKey: 'file',                  // optional; form field name (default: "file")
  file: '/path/to/photo.jpg',       // or file:///path/to/photo.jpg
  data: { userId: '123' },          // optional extra form fields
});

console.log(result.status);         // true if HTTP 2xx
console.log(result.httpStatus);     // e.g. 200
console.log(result.output);         // parsed JSON response body
```

### Upload multiple files

```ts
const result = await FileUploader.uploadFiles({
  url: 'https://api.example.com/upload',
  token: 'your-bearer-token',
  fileKey: 'files[]',               // optional (default: "files[]")
  files: [
    { path: '/path/to/a.jpg' },
    { path: 'file:///path/to/b.pdf' },
  ],
  data: { albumId: '42' },
});
```

### Resolve a content URI to a native path

Use this when a file picker returns an Android `content://` URI:

```ts
const { path } = await FileUploader.resolveNativePath({
  path: 'content://com.android.providers.media.documents/document/...',
});

// path is a filesystem path usable with uploadFile / uploadFiles
```

If direct resolution fails, the plugin copies the file into the app cache and returns that path.

### Download a file

Downloads to the public **Downloads** folder and emits progress events (see below).

```ts
const result = await FileUploader.downloadFile({
  path: 'https://example.com/report.pdf',
  name: 'report.pdf',
});

if (result.status) {
  console.log('Saved to', result.path); // file:///storage/.../Download/report.pdf
}
```

### Listen for download progress

Register the listener before calling `downloadFile`:

```ts
const handle = await FileUploader.addListener('downloadStatus', info => {
  // info: { path, start, finish, error, bytesDownloaded?, totalBytes?, message? }
  if (info.start) console.log('Download started');
  if (info.bytesDownloaded != null) {
    console.log(`${info.bytesDownloaded} / ${info.totalBytes}`);
  }
  if (info.finish) console.log('Download complete');
  if (info.error) console.log('Download failed');
});

await FileUploader.downloadFile({
  path: 'https://example.com/large-file.zip',
  name: 'large-file.zip',
});

await handle.remove();
```

### Open a downloaded file

Opens a file from the **Downloads** folder with the system viewer:

```ts
const result = await FileUploader.openFile({
  path: 'file:///storage/emulated/0/Download/report.pdf',
  type: 'application/pdf',          // optional (default: application/pdf)
});
```

## Android notes

- The plugin merges a `FileProvider` (`${applicationId}.fileprovider`) for opening files.
- Downloads are saved to `Environment.DIRECTORY_DOWNLOADS`.
- `openFile` looks for the file by name in the Downloads folder.
- On non-Android platforms, all methods throw: `FileUpload is not implemented on "<platform>". Android only plugin.`

## Development

Clone and build:

```bash
git clone https://github.com/pioneersingh321/file-uploader.git
cd file-uploader
npm install
npm run build
```

Watch TypeScript during development:

```bash
npm run watch
```

## API reference

| Method | Description |
|--------|-------------|
| `uploadFile(options)` | Multipart upload of one file |
| `uploadFiles(options)` | Multipart upload of multiple files |
| `resolveNativePath(options)` | Resolve `content://` or `file://` to a native path |
| `downloadFile(options)` | Download a URL to the Downloads folder |
| `openFile(options)` | Open a downloaded file with a system app |
| `addListener('downloadStatus', fn)` | Subscribe to download progress/completion |
| `removeAllListeners()` | Remove all plugin listeners |

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
