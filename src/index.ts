import { Capacitor, registerPlugin } from '@capacitor/core';
import type { FileUploaderPlugin } from './definitions';

const FileUploaderNative = registerPlugin<FileUploaderPlugin>('FileUpload', {
  web: () => import('./web').then(m => new m.FileUploaderWeb()),
});

const throwNotImplemented = () => {
  const platform = Capacitor.getPlatform();
  throw new Error(`FileUpload is not implemented on "${platform}".`);
};

const ensureNative = () => {
  const platform = Capacitor.getPlatform();
  if (platform !== 'android' && platform !== 'ios') {
    throwNotImplemented();
  }
};

const FileUploader: FileUploaderPlugin = {
  uploadFiles(options) {
    ensureNative();
    return FileUploaderNative.uploadFiles(options);
  },
  uploadFile(options) {
    ensureNative();
    return FileUploaderNative.uploadFile(options);
  },
  downloadFile(options) {
    ensureNative();
    return FileUploaderNative.downloadFile(options);
  },
  openFile(options) {
    ensureNative();
    return FileUploaderNative.openFile(options);
  },
  resolveNativePath(options) {
    ensureNative();
    return FileUploaderNative.resolveNativePath(options);
  },
  checkPermissions() {
    ensureNative();
    return FileUploaderNative.checkPermissions();
  },
  requestPermissions() {
    ensureNative();
    return FileUploaderNative.requestPermissions();
  },
  addListener(eventName, listenerFunc) {
    ensureNative();
    return FileUploaderNative.addListener(eventName, listenerFunc);
  },
  removeAllListeners() {
    ensureNative();
    return FileUploaderNative.removeAllListeners();
  },
};

export * from './definitions';
export { FileUploader };
