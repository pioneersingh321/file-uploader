import { WebPlugin } from '@capacitor/core';
import type {
  DownloadFileOptions,
  DownloadResult,
  FileUploaderPlugin,
  OpenFileOptions,
  OpenResult,
  ResolveNativePathOptions,
  ResolveNativePathResult,
  UploadFileOptions,
  UploadFilesOptions,
  UploadResult,
  PermissionStatus,
} from './definitions';

export class FileUploaderWeb extends WebPlugin implements FileUploaderPlugin {
  private notImplemented(): never {
    throw new Error('FileUpload is not implemented on web.');
  }

  async uploadFiles(_options: UploadFilesOptions): Promise<UploadResult> {
    this.notImplemented();
  }

  async uploadFile(_options: UploadFileOptions): Promise<UploadResult> {
    this.notImplemented();
  }

  async downloadFile(_options: DownloadFileOptions): Promise<DownloadResult> {
    this.notImplemented();
  }

  async openFile(_options: OpenFileOptions): Promise<OpenResult> {
    this.notImplemented();
  }

  async resolveNativePath(_options: ResolveNativePathOptions): Promise<ResolveNativePathResult> {
    this.notImplemented();
  }

  async checkPermissions(): Promise<PermissionStatus> {
    this.notImplemented();
  }

  async requestPermissions(): Promise<PermissionStatus> {
    this.notImplemented();
  }
}
