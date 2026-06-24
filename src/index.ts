import { Capacitor, registerPlugin } from '@capacitor/core';
import type { FileUploaderPlugin } from './definitions';

const FileUploaderNative = registerPlugin<FileUploaderPlugin>('FileUpload', {
  web: () => import('./web').then(m => new m.FileUploaderWeb()),
});

const throwNotImplemented = () => {
  const platform = Capacitor.getPlatform();
  throw new Error(`FileUpload is not implemented on "${platform}". Android only plugin.`);
};

const ensureAndroid = () => {
  if (Capacitor.getPlatform() !== 'android') {
    throwNotImplemented();
  }
};

const FileUploader: FileUploaderPlugin = {
  uploadFiles(options) {
    ensureAndroid();
    return FileUploaderNative.uploadFiles(options);
  },
  uploadFile(options) {
    ensureAndroid();
    return FileUploaderNative.uploadFile(options);
  },
  downloadFile(options) {
    ensureAndroid();
    return FileUploaderNative.downloadFile(options);
  },
  openFile(options) {
    ensureAndroid();
    return FileUploaderNative.openFile(options);
  },
  resolveNativePath(options) {
    ensureAndroid();
    return FileUploaderNative.resolveNativePath(options);
  },
  addListener(eventName, listenerFunc) {
    ensureAndroid();
    return FileUploaderNative.addListener(eventName, listenerFunc);
  },
  removeAllListeners() {
    ensureAndroid();
    return FileUploaderNative.removeAllListeners();
  },
};

export * from './definitions';
export { FileUploader };
