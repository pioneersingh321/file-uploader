#import <Capacitor/Capacitor.h>

CAP_PLUGIN(FileUploaderPlugin, "FileUpload",
           CAP_PLUGIN_METHOD(uploadFiles, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(uploadFile, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(downloadFile, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(openFile, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(resolveNativePath, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(checkPermissions, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(requestPermissions, CAPPluginReturnPromise);
)
