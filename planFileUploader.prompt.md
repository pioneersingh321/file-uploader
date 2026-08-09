## Plan: Analyze Capacitor File Uploader Project

TL;DR - Review source structure, native plugin implementations, and build packaging to produce a concise project analysis and identify any gaps or improvement areas.

**Steps**
1. Confirm the plugin architecture and entrypoints.
   - `src/index.ts`, `src/web.ts`, `src/definitions.ts` define the Capacitor plugin API.
   - `src/index.ts` wraps native plugin registration and enforces Android/iOS-only usage.
   - `src/web.ts` intentionally throws not implemented errors for web.
2. Document Android native behavior.
   - `android/src/main/java/bolt/fileuploader/capacitor/FileUploaderPlugin.java` implements uploadFiles, uploadFile, downloadFile, openFile, resolveNativePath, checkPermissions, requestPermissions.
   - Uploads use OkHttp and multipart form-data.
   - Downloads use AndroidNetworking and emit `downloadStatus` listener events.
   - File opening uses `FileProvider` and external intent.
   - `resolveNativePath` handles `file://` and `content://` URIs, with fallback copy to cache.
   - Permissions are requested for READ/WRITE external storage via Capacitor annotations.
3. Document iOS native behavior.
   - `ios/Plugin/FileUploaderPlugin.swift` implements equivalent plugin methods.
   - Uploads use `URLSession.uploadTask` and multipart body construction.
   - Downloads use a custom `FileDownloader` with progress events and save to app documents directory.
   - Open file uses `UIDocumentInteractionController`.
   - `resolveNativePath` normalizes `file://` paths only.
   - Permissions are stubbed as granted for storage.
4. Review packaging and build config.
   - `package.json` defines `main`, `module`, `types`, Capacitor plugin metadata, and build scripts using TypeScript + Rollup.
   - `tsconfig.json` targets ES2017 and outputs declarations to `dist/esm`.
5. Identify analysis outputs.
   - Provide a high-level summary of project purpose, supported platforms, API surface, native implementation details, and potential weaknesses.
   - Note Android/iOS feature parity differences and any missing web support.

**Relevant files**
- `src/index.ts`
- `src/web.ts`
- `src/definitions.ts`
- `android/src/main/java/bolt/fileuploader/capacitor/FileUploaderPlugin.java`
- `ios/Plugin/FileUploaderPlugin.swift`
- `package.json`
- `tsconfig.json`

**Verification**
1. Confirm that the plugin methods are consistent across web, Android, and iOS definitions.
2. Verify native Android and iOS upload/download/open logic matches README API.
3. Check build scripts and published exports are aligned with Capacitor plugin expectations.

**Decisions**
- Focus analysis on plugin implementation and feature coverage rather than on uncommitted build artifacts in `dist/`.
- Treat web as intentionally unsupported.

**Further Considerations**
1. Determine if the user wants a written project analysis summary or a remediation plan for issues found.
2. If needed, inspect Android manifest, iOS plugin registration, and `rollup.config.js` next.
