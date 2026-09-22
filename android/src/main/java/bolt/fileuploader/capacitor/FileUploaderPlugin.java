package bolt.fileuploader.capacitor;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;

import androidx.activity.result.ActivityResult;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
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
 *
 * <h2>File picker (pickFile / pickFiles)</h2>
 * Permissions are requested <em>before</em> opening the system file picker so that the
 * user is prompted at the natural "I want to select a file" moment, not at upload time.
 * The flow is:
 * <ol>
 *   <li>JS calls {@code pickFile} / {@code pickFiles}.</li>
 *   <li>Plugin checks / requests the appropriate storage permission.</li>
 *   <li>On grant: launches {@link Intent#ACTION_GET_CONTENT} (system file picker).</li>
 *   <li>{@link #onPickFileResult} / {@link #onPickFilesResult} receive the selection and
 *       resolve the call with the selected file path(s).</li>
 * </ol>
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

    private static final int REQUEST_PICK_FILE  = 10001;
    private static final int REQUEST_PICK_FILES = 10002;

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
    // pickFile — request permission → open picker → resolve with selected path
    // -------------------------------------------------------------------------

    /**
     * Presents the system file picker for a single file.
     *
     * <p>Permissions are requested <em>here</em> — before the picker opens — so the
     * system dialog appears in the context of the user's deliberate "pick a file" action
     * rather than later during the upload HTTP call.</p>
     *
     * <p>Accepted call options:</p>
     * <ul>
     *   <li>{@code mimeType} (string, optional) — MIME type filter passed to the picker,
     *       e.g. {@code "image/*"}, {@code "application/pdf"}.
     *       Defaults to {@code "*‌/*"} (all files).</li>
     * </ul>
     */
    @PluginMethod
    public void pickFile(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias(storagePermissionAlias(), call, "pickFilePermissionCallback");
        } else {
            launchPickFile(call);
        }
    }

    @PermissionCallback
    private void pickFilePermissionCallback(PluginCall call) {
        if (isStoragePermissionGranted()) {
            launchPickFile(call);
        } else {
            call.reject("Storage permission is required to select a file");
        }
    }

    private void launchPickFile(PluginCall call) {
        String mimeType = call.getString("mimeType", "*/*");
        if (FileUtils.isBlank(mimeType)) {
            mimeType = "*/*";
        }
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.setType(mimeType);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        // Single selection — do NOT set EXTRA_ALLOW_MULTIPLE.
        startActivityForResult(call, intent, "onPickFileResult");
    }

    @ActivityCallback
    private void onPickFileResult(PluginCall call, ActivityResult result) {
        if (call == null) {
            return;
        }
        if (result.getResultCode() != Activity.RESULT_OK || result.getData() == null) {
            call.reject("File selection was cancelled");
            return;
        }

        Uri uri = result.getData().getData();
        if (uri == null) {
            call.reject("No file was selected");
            return;
        }

        try {
            String resolvedPath = FileUtils.resolveNativePath(getContext(), uri.toString());
            if (FileUtils.isBlank(resolvedPath)) {
                call.reject("Unable to resolve selected file path");
                return;
            }

            String displayName = FileUtils.queryDisplayName(getContext(), uri);
            String mimeType = getContext().getContentResolver().getType(uri);

            JSObject file = new JSObject();
            file.put("path", resolvedPath);
            file.put("uri", uri.toString());
            if (displayName != null) file.put("name", displayName);
            if (mimeType != null)    file.put("mimeType", mimeType);

            JSObject res = new JSObject();
            res.put("file", file);
            call.resolve(res);
        } catch (Exception e) {
            call.reject("Failed to process selected file", e);
        }
    }

    // -------------------------------------------------------------------------
    // pickFiles — request permission → open picker (multi-select) → resolve paths
    // -------------------------------------------------------------------------

    /**
     * Presents the system file picker for multiple files.
     *
     * <p>Permissions are requested <em>before</em> the picker opens for the same reason
     * as {@link #pickFile}: the user is in the "I want to select files" context.</p>
     *
     * <p>Accepted call options:</p>
     * <ul>
     *   <li>{@code mimeType} (string, optional) — MIME type filter, e.g. {@code "image/*"}.
     *       Defaults to {@code "*‌/*"} (all files).</li>
     *   <li>{@code multiple} (boolean, optional) — when {@code true} enables multi-select.
     *       Defaults to {@code true}.</li>
     * </ul>
     */
    @PluginMethod
    public void pickFiles(PluginCall call) {
        if (!isStoragePermissionGranted()) {
            requestPermissionForAlias(storagePermissionAlias(), call, "pickFilesPermissionCallback");
        } else {
            launchPickFiles(call);
        }
    }

    @PermissionCallback
    private void pickFilesPermissionCallback(PluginCall call) {
        if (isStoragePermissionGranted()) {
            launchPickFiles(call);
        } else {
            call.reject("Storage permission is required to select files");
        }
    }

    private void launchPickFiles(PluginCall call) {
        String mimeType = call.getString("mimeType", "*/*");
        if (FileUtils.isBlank(mimeType)) {
            mimeType = "*/*";
        }
        boolean multiple = Boolean.TRUE.equals(call.getBoolean("multiple", true));

        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.setType(mimeType);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple);
        startActivityForResult(call, intent, "onPickFilesResult");
    }

    @ActivityCallback
    private void onPickFilesResult(PluginCall call, ActivityResult result) {
        if (call == null) {
            return;
        }
        if (result.getResultCode() != Activity.RESULT_OK || result.getData() == null) {
            call.reject("File selection was cancelled");
            return;
        }

        Intent data = result.getData();
        JSArray filesArray = new JSArray();

        try {
            // Multi-select: URIs are in the ClipData bundle.
            if (data.getClipData() != null && data.getClipData().getItemCount() > 0) {
                android.content.ClipData clipData = data.getClipData();
                for (int i = 0; i < clipData.getItemCount(); i++) {
                    Uri uri = clipData.getItemAt(i).getUri();
                    if (uri != null) {
                        filesArray.put(buildFileObject(uri));
                    }
                }
            } else if (data.getData() != null) {
                // Single selection even though multi was requested.
                filesArray.put(buildFileObject(data.getData()));
            } else {
                call.reject("No files were selected");
                return;
            }

            JSObject res = new JSObject();
            res.put("files", filesArray);
            call.resolve(res);
        } catch (Exception e) {
            call.reject("Failed to process selected files", e);
        }
    }

    /**
     * Builds a single-file JSObject from a content URI, resolving the native path and
     * querying display name and MIME type from the ContentResolver.
     */
    private JSObject buildFileObject(Uri uri) throws Exception {
        String resolvedPath = FileUtils.resolveNativePath(getContext(), uri.toString());
        String displayName  = FileUtils.queryDisplayName(getContext(), uri);
        String mimeType     = getContext().getContentResolver().getType(uri);

        JSObject file = new JSObject();
        file.put("path", resolvedPath != null ? resolvedPath : "");
        file.put("uri", uri.toString());
        if (displayName != null) file.put("name", displayName);
        if (mimeType != null)    file.put("mimeType", mimeType);
        return file;
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
