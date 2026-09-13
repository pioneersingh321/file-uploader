import { registerPlugin } from '@capacitor/core';
import type { FileUploaderPlugin } from './definitions';

const FileUploader = registerPlugin<FileUploaderPlugin>('FileUpload', {
  web: () => import('./web').then(m => new m.FileUploaderWeb()),
});

export * from './definitions';
export { FileUploader };
