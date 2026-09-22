package bolt.fileuploader.capacitor;

import android.Manifest;
import android.os.Build;

import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

/**
 * FileUploaderPlugin — Capacitor plugin entry point.
 *
 * <h2>Permission strategy</h2>
 * Android has had three distinct storage permission models across its history:
 *
 * <ul>
 *   <li><b>API &lt; 23 (pre-Marshmallow)</b>: all permissions are granted at install time;
 *       no runtime prompts are needed.</li>
 *   <li><b>API 23–28 (Marshmallow–Pie)</b>: {@code READ_EXTERNAL_STORAGE} and
 *       {@code WRITE_EXTERNAL_STORAGE} must be requested at runtime. Both are needed
 *       to read from and write to shared external storage.</li>
 *   <li><b>API 29–32 (Q–12L)</b>: Scoped storage is introduced. {@code WRITE_EXTERNAL_STORAGE}
 *       is no longer granted even if requested (it is silently ignored from API 30 onward).
 *       {@code READ_EXTERNAL_STORAGE} is still required to read files the app did not create.</li>
 *   <li><b>API 33+ (Tiramisu)</b>: {@code READ_EXTERNAL_STORAGE} is retired. Apps must request
 *       the granular {@code READ_MEDIA_IMAGES}, {@code READ_MEDIA_VIDEO}, and
 *       {@code READ_MEDIA_AUDIO} permissions to access media in shared storage.</li>
 * </ul>
 *
 * Two {@link Permission} aliases are declared so that Capacitor's permission machinery
 * can request the correct set for each API level:
 * <ul>
 *   <li>{@code "storage"} — legacy storage permissions (API 23–32).</li>
 *   <li>{@code "mediaStorage"} — granular media permissions (API 33+).</li>
 * </ul>
 */
@CapacitorPlugin(
    name = "FileUpload",
    permissions = {
        @Permission(
            alias = "storage",
            strings = {
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            }
        ),
        @Permission(
            alias = "mediaStorage",
            strings = {
                // These constants are defined from API 33. The string literals are used
                // directly so the library compiles against older compileSdk values too.
                // At runtime the @CapacitorPlugin processor handles version gating.
                "android.permission.READ_MEDIA_IMAGES",
                "android.permission.READ_MEDIA_VIDEO",
                "android.permission.READ_MEDIA_AUDIO"
            }
        )
    }
)
public class FileUploaderPlugin extends Plugin {

    private final FileUploadManager uploadManager = new FileUploadManager();

    /**
     * Returns true when the runtime has the storage permissions appropriate for the
     * running Android version, or when no runtime permission is required (API &lt; 23).
     *
     * <ul>
     *   <li>API &lt; 23: install-time permissions — always considered granted.</li>
     *   <li>API 23–32: check the {@code "storage"} alias
     *       ({@code READ_EXTERNAL_STORAGE} + {@code WRITE_EXTERNAL_STORAGE}).</li>
     *   <li>API 33+: check the {@code "mediaStorage"} alias
     *       ({@code READ_MEDIA_IMAGES}, {@code READ_MEDIA_VIDEO}, {@code READ_MEDIA_AUDIO}).</li>
     * </ul>
     */
    private boolean isStoragePermissionGranted() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // Pre-Marshmallow: all permissions are granted at install time.
            return true;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // API 33+: need at least one of the granular media permissions.
            // We treat any GRANTED media permission as sufficient so that apps
            // which only handle (e.g.) images do not have to grant all three.
            return getPermissionState("mediaStorage") == PermissionState.GRANTED;
        }
        // API 23–32: classic READ + WRITE storage alias.
        return getPermissionState("storage") == PermissionState.GRANTED;
    }

    /**
     * Returns the permission alias that should be requested for the current API level.
     * Used when we need to ask the user for storage access.
     */
    private String storagePermissionAlias() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
            ? "mediaStorage"
            : "storage";
    }

    // -------------------------------------------------------------------------
    // uploadFiles
    // -------------------------------------------------------------------------

    @PluginMethod
    public void uploadFiles(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias(storagePermissionAlias(), call, "uploadFilesPermissionCallback");
        } else {
            uploadManager.startUploadFiles(getContext(), call);
        }
    }

    @PermissionCallback
    private void uploadFilesPermissionCallback(PluginCall call) {
        if (isStoragePermissionGranted()) {
            uploadManager.startUploadFiles(getContext(), call);
        } else {
            call.reject("Storage permission is required to upload files");
        }
    }

    // -------------------------------------------------------------------------
    // uploadFile
    // -------------------------------------------------------------------------

    @PluginMethod
    public void uploadFile(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias(storagePermissionAlias(), call, "uploadFilePermissionCallback");
        } else {
            uploadManager.startUploadFile(getContext(), call);
        }
    }

    @PermissionCallback
    private void uploadFilePermissionCallback(PluginCall call) {
        if (isStoragePermissionGranted()) {
            uploadManager.startUploadFile(getContext(), call);
        } else {
            call.reject("Storage permission is required to upload file");
        }
    }

    // -------------------------------------------------------------------------
    // downloadFile
    // -------------------------------------------------------------------------

    @PluginMethod
    public void downloadFile(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias(storagePermissionAlias(), call, "downloadPermissionCallback");
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

    // -------------------------------------------------------------------------
    // openFile — no storage permission needed; FileProvider handles URI sharing
    // -------------------------------------------------------------------------

    @PluginMethod
    public void openFile(PluginCall call) {
        FileOpenerManager.openFile(getContext(), call);
    }

    // -------------------------------------------------------------------------
    // resolveNativePath
    // -------------------------------------------------------------------------

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
