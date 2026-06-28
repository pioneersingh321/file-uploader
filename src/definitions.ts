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
  output: unknown;
  status: boolean;
  httpStatus?: number;
}

export interface DownloadFileOptions {
  path: string;
  name: string;
}

export interface DownloadResult {
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
  path: string;
  start: boolean;
  finish: boolean;
  error: boolean;
  bytesDownloaded?: number;
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
