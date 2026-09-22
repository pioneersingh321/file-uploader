import type { PluginListenerHandle, PermissionState } from '@capacitor/core';

export interface PermissionStatus {
  /** Legacy storage permission state (Android 6–12L, API 23–32). */
  storage?: PermissionState;
  /**
   * Granular media permission state (Android 13+, API 33+).
   * Reflects READ_MEDIA_IMAGES / READ_MEDIA_VIDEO / READ_MEDIA_AUDIO.
   */
  mediaStorage?: PermissionState;
}

/** A single file returned by {@link FileUploaderPlugin.pickFile} or {@link FileUploaderPlugin.pickFiles}. */
export interface PickedFile {
  /**
   * The resolved native filesystem path of the selected file.
   * On Android 29+, this will be a path inside the app's cache directory
   * (the file is copied there from the content URI so it can be opened directly).
   */
  path: string;
  /** The original content:// or file:// URI as returned by the OS file picker. */
  uri: string;
  /** Display name of the file as reported by the ContentResolver / DocumentProvider. */
  name?: string;
  /** MIME type of the selected file, e.g. `"image/jpeg"`. */
  mimeType?: string;
}

export interface PickFileOptions {
  /**
   * MIME type filter passed to the OS file picker.
   * Use `"image/*"` to show only images, `"application/pdf"` for PDFs, etc.
   * Defaults to `"*\/*"` (all file types).
   */
  mimeType?: string;
}

export interface PickFileResult {
  file: PickedFile;
}

export interface PickFilesOptions {
  /**
   * MIME type filter passed to the OS file picker.
   * Defaults to `"*\/*"` (all file types).
   */
  mimeType?: string;
  /**
   * Allow the user to select more than one file.
   * Defaults to `true`.
   */
  multiple?: boolean;
}

export interface PickFilesResult {
  files: PickedFile[];
}

export interface UploadFileItem {
  path: string;
}

export interface UploadFilesOptions {
  url: string;
  token?: string;
  data?: Record<string, unknown>;
  fileKey?: string;
  files: UploadFileItem[];
}

export interface UploadFileOptions {
  url: string;
  token?: string;
  data?: Record<string, unknown>;
  fileKey?: string;
  file: string;
}

export interface UploadResult {
  /**
   * The parsed server response body.
   *
   * Shape variants (consistent across iOS and Android):
   * - **JSON object** → the object itself, e.g. `{ id: 1, name: "..." }`
   * - **JSON array**  → wrapped as `{ items: [...] }` — top-level arrays are
   *   normalized to an object on both platforms to maintain a consistent contract.
   * - **Scalar JSON** → wrapped as `{ value: <scalar> }`.
   * - **Non-JSON**    → wrapped as `{ raw: "<string>" }`.
   * - **Error / no body** → `{}` or `{ raw: "<error message>" }`.
   *
   * Use `TypeGuards.isUploadResult` to narrow before accessing fields.
   */
  output: unknown;
  /** `true` when the HTTP status code is in the 200–299 range. */
  status: boolean;
  /** The raw HTTP status code returned by the server. */
  httpStatus?: number;
}

export interface DownloadFileOptions {
  path: string;
  name: string;
}

export interface DownloadResult {
  /**
   * The destination file URI.
   * Always a `file://` URI (e.g. `file:///var/mobile/…`).
   * Consistent across all `downloadStatus` events and the final resolve.
   */
  path: string;
  status: boolean;
  error: boolean;
  message?: string;
}

export interface OpenFileOptions {
  path: string;
  type?: string;
}

export interface OpenResult {
  path?: string;
  status: boolean;
  error: boolean;
  message?: string;
}

export interface ResolveNativePathOptions {
  path: string;
}

export interface ResolveNativePathResult {
  path: string;
}

export interface DownloadStatusInfo {
  /**
   * The destination file URI. Always a `file://` URI.
   * Consistent across start, progress, finish, and error events.
   */
  path: string;
  start: boolean;
  finish: boolean;
  error: boolean;
  /**
   * Bytes downloaded so far. Clamped to `Number.MAX_SAFE_INTEGER` (9,007,199,254,740,991)
   * on both platforms to prevent IEEE-754 double precision loss for very large files.
   */
  bytesDownloaded?: number;
  /**
   * Total expected bytes. Clamped to `Number.MAX_SAFE_INTEGER` on both platforms.
   * May be -1 when the server does not send a Content-Length header.
   */
  totalBytes?: number;
  message?: string;
}

export type PostOptions = UploadFilesOptions;

export interface FileUploaderPlugin {
  /**
   * Checks storage permissions and, if granted, presents the OS file picker for a
   * **single** file selection. The permission prompt (if needed) fires here — at the
   * moment the user initiates file selection — rather than at upload time.
   *
   * @param options.mimeType MIME type filter, e.g. `"image/*"`. Defaults to `"*\/*"`.
   * @returns The selected file with its resolved native path, URI, name, and mimeType.
   */
  pickFile(options?: PickFileOptions): Promise<PickFileResult>;

  /**
   * Checks storage permissions and, if granted, presents the OS file picker for
   * **multiple** file selection. The permission prompt fires here, before the picker opens.
   *
   * @param options.mimeType MIME type filter. Defaults to `"*\/*"`.
   * @param options.multiple Enable multi-select. Defaults to `true`.
   * @returns An array of selected files, each with its resolved native path.
   */
  pickFiles(options?: PickFilesOptions): Promise<PickFilesResult>;

  uploadFiles(options: UploadFilesOptions): Promise<UploadResult>;
  uploadFile(options: UploadFileOptions): Promise<UploadResult>;
  downloadFile(options: DownloadFileOptions): Promise<DownloadResult>;
  openFile(options: OpenFileOptions): Promise<OpenResult>;
  resolveNativePath(options: ResolveNativePathOptions): Promise<ResolveNativePathResult>;
  checkPermissions(): Promise<PermissionStatus>;
  requestPermissions(): Promise<PermissionStatus>;

  addListener(
    eventName: 'downloadStatus',
    listenerFunc: (info: DownloadStatusInfo) => void,
  ): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}

// ---------------------------------------------------------------------------
// Runtime Type Guards
// ---------------------------------------------------------------------------

/**
 * Runtime type guard utilities for safely narrowing plugin return values.
 *
 * Because the Capacitor bridge serializes data through JSON, the TypeScript
 * compiler cannot guarantee the runtime shape of values received from native
 * code. These guards provide explicit runtime checks at the JS boundary.
 *
 * @example
 * ```ts
 * import { FileUploader, TypeGuards } from '@bolt/file-uploader';
 *
 * const result = await FileUploader.uploadFile({ url, file });
 * if (TypeGuards.isUploadResult(result)) {
 *   console.log(result.status, result.httpStatus);
 * }
 *
 * FileUploader.addListener('downloadStatus', (info) => {
 *   if (TypeGuards.isDownloadStatusInfo(info)) {
 *     console.log(info.bytesDownloaded, '/', info.totalBytes);
 *   }
 * });
 * ```
 */
export namespace TypeGuards {
  /**
   * Checks that `v` has the required fields of `UploadResult`.
   * Does NOT validate the `output` field shape — use `hasRawOutput` or
   * `hasItemsOutput` for that.
   */
  export function isUploadResult(v: unknown): v is UploadResult {
    if (v === null || typeof v !== 'object') return false;
    const r = v as Record<string, unknown>;
    return (
      'status' in r && typeof r['status'] === 'boolean' &&
      'output' in r
    );
  }

  /** Returns `true` if the upload `output` was a non-JSON response wrapped as `{ raw: string }`. */
  export function hasRawOutput(output: unknown): output is { raw: string } {
    if (output === null || typeof output !== 'object') return false;
    const o = output as Record<string, unknown>;
    return 'raw' in o && typeof o['raw'] === 'string';
  }

  /** Returns `true` if the upload `output` was a top-level JSON array, wrapped as `{ items: unknown[] }`. */
  export function hasItemsOutput(output: unknown): output is { items: unknown[] } {
    if (output === null || typeof output !== 'object') return false;
    const o = output as Record<string, unknown>;
    return 'items' in o && Array.isArray(o['items']);
  }

  /** Checks that `v` has the required fields of `DownloadResult`. */
  export function isDownloadResult(v: unknown): v is DownloadResult {
    if (v === null || typeof v !== 'object') return false;
    const r = v as Record<string, unknown>;
    return (
      'path' in r && typeof r['path'] === 'string' &&
      'status' in r && typeof r['status'] === 'boolean' &&
      'error' in r && typeof r['error'] === 'boolean'
    );
  }

  /** Checks that `v` has the required fields of `DownloadStatusInfo`. */
  export function isDownloadStatusInfo(v: unknown): v is DownloadStatusInfo {
    if (v === null || typeof v !== 'object') return false;
    const r = v as Record<string, unknown>;
    return (
      'path' in r && typeof r['path'] === 'string' &&
      'start' in r && typeof r['start'] === 'boolean' &&
      'finish' in r && typeof r['finish'] === 'boolean' &&
      'error' in r && typeof r['error'] === 'boolean'
    );
  }

  /** Checks that `v` has the required fields of `OpenResult`. */
  export function isOpenResult(v: unknown): v is OpenResult {
    if (v === null || typeof v !== 'object') return false;
    const r = v as Record<string, unknown>;
    return (
      'status' in r && typeof r['status'] === 'boolean' &&
      'error' in r && typeof r['error'] === 'boolean'
    );
  }
}
