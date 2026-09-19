import type { PluginListenerHandle, PermissionState } from '@capacitor/core';

export interface PermissionStatus {
  storage: PermissionState;
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
