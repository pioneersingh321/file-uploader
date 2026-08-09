package bolt.fileuploader.capacitor;

import android.Manifest;

import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

@CapacitorPlugin(
    name = "FileUpload",
    permissions = {
        @Permission(
            alias = "storage",
            strings = {
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            }
        )
    }
)
public class FileUploaderPlugin extends Plugin {

    private final FileUploadManager uploadManager = new FileUploadManager();

    private boolean isStoragePermissionGranted() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            return true;
        }
        return getPermissionState("storage") == PermissionState.GRANTED;
    }

    @PluginMethod
    public void uploadFiles(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias("storage", call, "uploadFilesPermissionCallback");
        } else {
            uploadManager.startUploadFiles(call);
        }
    }

    @PermissionCallback
    private void uploadFilesPermissionCallback(PluginCall call) {
        if (isStoragePermissionGranted()) {
            uploadManager.startUploadFiles(call);
        } else {
            call.reject("Storage permission is required to upload files");
        }
    }

    @PluginMethod
    public void uploadFile(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias("storage", call, "uploadFilePermissionCallback");
        } else {
            uploadManager.startUploadFile(call);
        }
    }

    @PermissionCallback
    private void uploadFilePermissionCallback(PluginCall call) {
        if (isStoragePermissionGranted()) {
            uploadManager.startUploadFile(call);
        } else {
            call.reject("Storage permission is required to upload file");
        }
    }

    @PluginMethod
    public void downloadFile(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias("storage", call, "downloadPermissionCallback");
        } else {
            startDownloadFile(call);
        }
    }

    @PermissionCallback
    private void downloadPermissionCallback(PluginCall call) {
        if (isStoragePermissionGranted()) {
            startDownloadFile(call);
        } else {
            call.reject("Storage permission is required to download files");
        }
    }

    private void startDownloadFile(PluginCall call) {
        FileDownloadManager.startDownloadFile(getContext(), call, this::notifyListeners);
    }

    @PluginMethod
    public void openFile(PluginCall call) {
        FileOpenerManager.openFile(getContext(), call);
    }

    @PluginMethod
    public void resolveNativePath(PluginCall call) {
        String path = call.getString("path");
        if (FileUtils.isBlank(path)) {
            call.reject("path is required");
            return;
        }

        try {
            String resolvedPath = FileUtils.resolveNativePath(getContext(), path);
            if (FileUtils.isBlank(resolvedPath)) {
                call.reject("Unable to resolve native path");
                return;
            }

            JSObject result = new JSObject();
            result.put("path", resolvedPath);
            call.resolve(result);
        } catch (Exception e) {
            call.reject("Failed to resolve native path", e);
        }
    }
}
