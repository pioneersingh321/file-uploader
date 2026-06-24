package bolt.fileuploader.capacitor;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.util.Log;
import android.webkit.MimeTypeMap;

import androidx.core.content.FileProvider;

import com.androidnetworking.AndroidNetworking;
import com.androidnetworking.common.Priority;
import com.androidnetworking.error.ANError;
import com.androidnetworking.interfaces.DownloadListener;
import com.androidnetworking.interfaces.DownloadProgressListener;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.URI;
import java.util.Iterator;
import java.util.Locale;

import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

@CapacitorPlugin(name = "FileUpload")
public class FileUploaderPlugin extends Plugin {

    private final OkHttpClient client = new OkHttpClient();

    @PluginMethod
    public void uploadFiles(PluginCall call) {
        String url = call.getString("url");
        String token = call.getString("token", "");
        JSObject data = call.getObject("data", new JSObject());
        String fileKey = call.getString("fileKey", "files[]");
        JSArray files = call.getArray("files");

        if (isBlank(url)) {
            call.reject("url is required");
            return;
        }
        final String urlValue = url.trim();
        final String tokenValue = token != null ? token : "";
        final String uploadKey = isBlank(fileKey) ? "files[]" : fileKey.trim();

        if (files == null || files.length() == 0) {
            call.reject("files is required and cannot be empty");
            return;
        }

        MultipartBody.Builder requestBody = new MultipartBody.Builder().setType(MultipartBody.FORM);
        try {
            for (int i = 0; i < files.length(); i++) {
                JSONObject row = files.getJSONObject(i);
                String filePathValue = row.optString("path", "").trim();
                if (filePathValue.isEmpty()) {
                    continue;
                }

                File file = getFileFromUriString(filePathValue);
                if (!file.exists()) {
                    continue;
                }

                String fileNameUpload = file.getName().trim();
                String mimeType = getMimeTypeFromFileName(fileNameUpload);
                if (mimeType == null) {
                    mimeType = "application/octet-stream";
                }

              MediaType mediaType = MediaType.parse(mimeType);
              if (mediaType == null) {
                mediaType = MediaType.parse("application/octet-stream");
              }
              RequestBody body = RequestBody.create(file, mediaType);
              requestBody.addFormDataPart(uploadKey, fileNameUpload, body);
            }

            if (data != null) {
                Iterator<String> keys = data.keys();
                while (keys.hasNext()) {
                    String key = keys.next();
                    try {
                        Object value = data.get(key);
                        requestBody.addFormDataPart(key, String.valueOf(value));
                    } catch (JSONException ignored) {
                    }
                }
            }
        } catch (Exception e) {
            call.reject("Failed to build upload request", e);
            return;
        }

        executeUpload(call, urlValue, tokenValue, requestBody.build());
    }

    @PluginMethod
    public void uploadFile(PluginCall call) {
        String url = call.getString("url");
        String token = call.getString("token", "");
        JSObject data = call.getObject("data", null);
        String fileKey = call.getString("fileKey", "file");
        String filePath = call.getString("file");

        if (isBlank(url)) {
            call.reject("url is required");
            return;
        }
        final String urlValue = url.trim();
        final String tokenValue = token != null ? token : "";

        if (isBlank(filePath)) {
            call.reject("file is required");
            return;
        }
        final String filePathValue = filePath.trim();
        final String uploadKey = isBlank(fileKey) ? "file" : fileKey.trim();

        MultipartBody.Builder requestBody = new MultipartBody.Builder().setType(MultipartBody.FORM);
        try {
            File file = getFileFromUriString(filePathValue);
            String fileNameUpload = file.getName().trim();
            String mimeType = getMimeTypeFromFileName(fileNameUpload);
            if (mimeType == null) {
                mimeType = "application/octet-stream";
            }

             MediaType mediaType = MediaType.parse(mimeType);
              if (mediaType == null) {
                mediaType = MediaType.parse("application/octet-stream");
              }
              RequestBody body = RequestBody.create(file, mediaType);
              requestBody.addFormDataPart(uploadKey, fileNameUpload, body);


            if (data != null) {
                Iterator<String> keys = data.keys();
                while (keys.hasNext()) {
                    String key = keys.next();
                    try {
                        Object value = data.get(key);
                        requestBody.addFormDataPart(key, String.valueOf(value));
                    } catch (JSONException ignored) {
                    }
                }
            }
        } catch (Exception e) {
            call.reject("Failed to prepare file upload", e);
            return;
        }

        executeUpload(call, urlValue, tokenValue, requestBody.build());
    }

    @PluginMethod
    public void downloadFile(PluginCall call) {
        String path = call.getString("path");
        String fileName = call.getString("name");

        if (isBlank(path)) {
            call.reject("path is required");
            return;
        }
        if (isBlank(fileName)) {
            call.reject("name is required");
            return;
        }
        final String pathValue = path.trim();
        final String fileNameValue = fileName.trim();

        JSObject start = new JSObject();
        start.put("path", pathValue);
        start.put("start", true);
        start.put("finish", false);
        start.put("error", false);
        notifyListeners("downloadStatus", start);

        AndroidNetworking.initialize(getContext().getApplicationContext());

        String downloadDir =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).toString();
        String downloadPath = downloadDir + "/" + fileNameValue;

        AndroidNetworking.download(pathValue, downloadDir, fileNameValue)
            .setTag("Downloading - " + fileNameValue)
            .setPriority(Priority.MEDIUM)
            .setPercentageThresholdForCancelling(50)
            .build()
            .setDownloadProgressListener(
                (DownloadProgressListener) (bytesDownloaded, totalBytes) -> {
                    JSObject progress = new JSObject();
                    progress.put("path", "file://" + downloadPath);
                    progress.put("start", false);
                    progress.put("finish", false);
                    progress.put("error", false);
                    progress.put("bytesDownloaded", bytesDownloaded);
                    progress.put("totalBytes", totalBytes);
                    notifyListeners("downloadStatus", progress);
                }
            )
            .startDownload(
                new DownloadListener() {
                    @Override
                    public void onDownloadComplete() {
                        JSObject finish = new JSObject();
                        finish.put("path", "file://" + downloadPath);
                        finish.put("start", false);
                        finish.put("finish", true);
                        finish.put("error", false);
                        notifyListeners("downloadStatus", finish);

                        JSObject result = new JSObject();
                        result.put("path", "file://" + downloadPath);
                        result.put("error", false);
                        result.put("status", true);
                        call.resolve(result);
                    }

                    @Override
                    public void onError(ANError error) {
                        Log.d("FileUpload", "download error: " + error.getErrorDetail());

                        JSObject finish = new JSObject();
                        finish.put("path", "file://" + downloadPath);
                        finish.put("start", false);
                        finish.put("finish", false);
                        finish.put("error", true);
                        notifyListeners("downloadStatus", finish);

                        JSObject result = new JSObject();
                        result.put("path", "file://" + downloadPath);
                        result.put("error", true);
                        result.put("status", false);
                        result.put("message", error.getErrorDetail());
                        call.resolve(result);
                    }
                }
            );
    }

    @PluginMethod
    public void openFile(PluginCall call) {
        String filePath = call.getString("path");
        String fileType = call.getString("type", "application/pdf");

        if (isBlank(filePath)) {
            call.reject("path is required");
            return;
        }
        String filePathValue = filePath.trim();
        String fileTypeValue = isBlank(fileType) ? "application/pdf" : fileType.trim();

        File inputFile = new File(filePathValue.replace("file://", ""));
        String storage =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).toString() +
                "/" + inputFile.getName();
        File downloadFile = new File(storage);

        if (!downloadFile.exists()) {
            JSObject result = new JSObject();
            result.put("status", false);
            result.put("error", true);
            result.put("message", "File not found in Downloads");
            result.put("path", storage);
            call.resolve(result);
            return;
        }

        try {
            Uri pathUri = FileProvider.getUriForFile(
                getContext().getApplicationContext(),
                getContext().getApplicationContext().getPackageName() + ".fileprovider",
                downloadFile
            );
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(pathUri, fileTypeValue);
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            getContext().startActivity(intent);

            JSObject result = new JSObject();
            result.put("status", true);
            result.put("error", false);
            result.put("path", downloadFile.getAbsolutePath());
            call.resolve(result);
        } catch (ActivityNotFoundException e) {
            call.reject("No app found to open this file type", e);
        } catch (Exception e) {
            call.reject("Unable to open file", e);
        }
    }

    @PluginMethod
    public void resolveNativePath(PluginCall call) {
        String path = call.getString("path");
        if (isBlank(path)) {
            call.reject("path is required");
            return;
        }

        try {
            Uri uri = Uri.parse(path);
            String scheme = uri.getScheme();
            String resolvedPath;
            if (scheme != null && "file".equals(scheme.toLowerCase(Locale.ROOT))) {
                resolvedPath = uri.getPath() != null ? uri.getPath() : path;
            } else if (scheme != null && "content".equals(scheme.toLowerCase(Locale.ROOT))) {
                String direct = resolveContentUriToPath(uri);
                if (direct != null) {
                    resolvedPath = direct;
                } else {
                    File copied = copyContentUriToCache(uri);
                    resolvedPath = copied != null ? copied.getAbsolutePath() : null;
                }
            } else {
                resolvedPath = path;
            }

            if (isBlank(resolvedPath)) {
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

    private void executeUpload(PluginCall call, String url, String token, MultipartBody postBody) {
        Request request = new Request.Builder()
            .url(url)
            .header("Authorization", "Bearer " + token)
            .post(postBody)
            .build();

        JSObject obj = new JSObject();
        try (Response response = client.newCall(request).execute()) {
            String responseBody = response.body() != null ? response.body().string() : "{}";
            JSONObject resultObject;
            try {
                resultObject = new JSONObject(responseBody);
            } catch (JSONException ignored) {
                resultObject = new JSONObject();
                resultObject.put("raw", responseBody);
            }

            obj.put("output", resultObject);
            obj.put("status", response.isSuccessful());
            obj.put("httpStatus", response.code());
            call.resolve(obj);
        } catch (Exception e) {
            obj.put("output", e.getMessage());
            obj.put("status", false);
            call.resolve(obj);
        }
    }

    private String resolveContentUriToPath(Uri uri) {
        String[] projection = new String[]{MediaStore.MediaColumns.DATA};
        Cursor cursor = null;
        try {
            cursor = getContext().getContentResolver().query(uri, projection, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int columnIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATA);
                return columnIndex >= 0 ? cursor.getString(columnIndex) : null;
            }
            return null;
        } catch (Exception ignored) {
            return null;
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
    }

    private File copyContentUriToCache(Uri uri) {
        InputStream inputStream = null;
        try {
            inputStream = getContext().getContentResolver().openInputStream(uri);
            if (inputStream == null) {
                return null;
            }

            String fileName = queryDisplayName(uri);
            if (fileName == null) {
                fileName = "upload_" + System.currentTimeMillis();
            }
            String safeName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");
            File outputFile = new File(getContext().getCacheDir(), safeName);

            try (InputStream input = inputStream; FileOutputStream output = new FileOutputStream(outputFile)) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = input.read(buffer)) != -1) {
                    output.write(buffer, 0, read);
                }
            }
            return outputFile;
        } catch (Exception ignored) {
            return null;
        }
    }

    private String queryDisplayName(Uri uri) {
        Cursor cursor = null;
        try {
            cursor =
                getContext()
                    .getContentResolver()
                    .query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                return idx >= 0 ? cursor.getString(idx) : null;
            }
            return null;
        } catch (Exception ignored) {
            return null;
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
    }

    private File getFileFromUriString(String filePath) {
        return filePath.startsWith("file://") ? new File(URI.create(filePath)) : new File(filePath);
    }

    private String getMimeTypeFromFileName(String fileName) {
        if (isBlank(fileName) || !fileName.contains(".")) {
            return null;
        }
        int extIndex = fileName.lastIndexOf('.') + 1;
        String extension = fileName.substring(extIndex).toLowerCase(Locale.ROOT);
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
