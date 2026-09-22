package bolt.fileuploader.capacitor;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;

import androidx.activity.result.ActivityResult;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * FileUploaderPlugin — Capacitor plugin entry point.
 *
 * <p>File selection uses the system picker ({@link Intent#ACTION_GET_CONTENT}),
 * which grants the application temporary read URI permissions directly from Android.
 * Selected files are resolved to the app's cache directory via ContentResolver streams.
 * No shared storage permissions ({@code READ_EXTERNAL_STORAGE}, {@code WRITE_EXTERNAL_STORAGE},
 * or {@code READ_MEDIA_*}) are required.</p>
 */
@CapacitorPlugin(name = "FileUpload")
public class FileUploaderPlugin extends Plugin {

    private final FileUploadManager uploadManager = new FileUploadManager();

    // -------------------------------------------------------------------------
    // pickFile — open system picker → resolve with selected file info
    // -------------------------------------------------------------------------

    /**
     * Presents the system file picker for a single file.
     *
     * <p>Accepted call options:</p>
     * <ul>
     *   <li>{@code mimeType} (string, optional) — MIME type filter passed to the picker,
     *       e.g. {@code "image/*"}, {@code "application/pdf"}.
     *       Defaults to {@code "*/*"} (all files).</li>
     * </ul>
     */
    @PluginMethod
    public void pickFile(PluginCall call) {
        launchPickFile(call);
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

            JSObject fileObj = new JSObject();
            fileObj.put("path", resolvedPath);
            fileObj.put("uri", uri.toString());
            if (displayName != null) {
                fileObj.put("name", displayName);
            }
            if (mimeType != null) {
                fileObj.put("mimeType", mimeType);
            }

            JSObject res = new JSObject();
            res.put("file", fileObj);
            call.resolve(res);
        } catch (Exception e) {
            call.reject("Failed to process selected file", e);
        }
    }

    // -------------------------------------------------------------------------
    // pickFiles — open system picker (multi-select) → resolve paths
    // -------------------------------------------------------------------------

    /**
     * Presents the system file picker for multiple files.
     *
     * <p>Accepted call options:</p>
     * <ul>
     *   <li>{@code mimeType} (string, optional) — MIME type filter, e.g. {@code "image/*"}.
     *       Defaults to {@code "*/*"} (all files).</li>
     *   <li>{@code multiple} (boolean, optional) — when {@code true} enables multi-select.
     *       Defaults to {@code true}.</li>
     * </ul>
     */
    @PluginMethod
    public void pickFiles(PluginCall call) {
        launchPickFiles(call);
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
        uploadManager.startUploadFiles(getContext(), call);
    }

    // -------------------------------------------------------------------------
    // uploadFile
    // -------------------------------------------------------------------------

    @PluginMethod
    public void uploadFile(PluginCall call) {
        uploadManager.startUploadFile(getContext(), call);
    }

    // -------------------------------------------------------------------------
    // downloadFile
    // -------------------------------------------------------------------------

    @PluginMethod
    public void downloadFile(PluginCall call) {
        startDownloadFile(call);
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
