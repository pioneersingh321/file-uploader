import { WebPlugin } from '@capacitor/core';
import type {
  DownloadFileOptions,
  DownloadResult,
  FileUploaderPlugin,
  OpenFileOptions,
  OpenResult,
  PickFileOptions,
  PickFileResult,
  PickFilesOptions,
  PickFilesResult,
  ResolveNativePathOptions,
  ResolveNativePathResult,
  UploadFileOptions,
  UploadFilesOptions,
  UploadResult,
  PermissionStatus,
} from './definitions';

export class FileUploaderWeb extends WebPlugin implements FileUploaderPlugin {
  async pickFile(_options?: PickFileOptions): Promise<PickFileResult> {
    throw this.unimplemented('pickFile is not implemented on web.');
  }

  async pickFiles(_options?: PickFilesOptions): Promise<PickFilesResult> {
    throw this.unimplemented('pickFiles is not implemented on web.');
  }

  async uploadFiles(_options: UploadFilesOptions): Promise<UploadResult> {
    throw this.unimplemented('uploadFiles is not implemented on web.');
  }

  async uploadFile(_options: UploadFileOptions): Promise<UploadResult> {
    throw this.unimplemented('uploadFile is not implemented on web.');
  }

  async downloadFile(_options: DownloadFileOptions): Promise<DownloadResult> {
    throw this.unimplemented('downloadFile is not implemented on web.');
  }

  async openFile(_options: OpenFileOptions): Promise<OpenResult> {
    throw this.unimplemented('openFile is not implemented on web.');
  }

  async resolveNativePath(_options: ResolveNativePathOptions): Promise<ResolveNativePathResult> {
    throw this.unimplemented('resolveNativePath is not implemented on web.');
  }

  async checkPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('checkPermissions is not implemented on web.');
  }

  async requestPermissions(): Promise<PermissionStatus> {
    throw this.unimplemented('requestPermissions is not implemented on web.');
  }
}
