package bolt.fileuploader.capacitor;

import android.content.Context;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.Iterator;

import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class FileUploadManager {

    private final OkHttpClient client;

    public FileUploadManager() {
        this.client = new OkHttpClient();
    }

    public FileUploadManager(OkHttpClient client) {
        this.client = client != null ? client : new OkHttpClient();
    }

    public void startUploadFile(Context context, PluginCall call) {
        String url = call.getString("url");
        String token = call.getString("token", "");
        JSObject data = call.getObject("data", null);
        String fileKey = call.getString("fileKey", "file");
        String filePath = call.getString("file");

        if (FileUtils.isBlank(url)) {
            call.reject("url is required");
            return;
        }
        final String urlValue = url.trim();
        final String tokenValue = token != null ? token.trim() : "";

        if (FileUtils.isBlank(filePath)) {
            call.reject("file is required");
            return;
        }
        final String filePathValue = filePath.trim();
        final String uploadKey = FileUtils.isBlank(fileKey) ? "file" : fileKey.trim();

        MultipartBody.Builder requestBody = new MultipartBody.Builder().setType(MultipartBody.FORM);
        try {
            String resolvedPath = FileUtils.resolveNativePath(context, filePathValue);
            if (FileUtils.isBlank(resolvedPath)) {
                call.reject("Unable to resolve file path: " + filePathValue);
                return;
            }

            File file = new File(resolvedPath);
            if (!file.exists()) {
                call.reject("File does not exist: " + resolvedPath);
                return;
            }

            String fileNameUpload = file.getName().trim();
            String mimeType = FileUtils.getMimeTypeFromFileName(fileNameUpload);
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
                appendFormData(requestBody, data);
            }
        } catch (Exception e) {
            call.reject("Failed to prepare file upload: " + e.getMessage(), e);
            return;
        }

        executeUpload(call, urlValue, tokenValue, requestBody.build());
    }

    public void startUploadFiles(Context context, PluginCall call) {
        String url = call.getString("url");
        String token = call.getString("token", "");
        JSObject data = call.getObject("data", null);
        String fileKey = call.getString("fileKey", "files[]");
        JSArray files = call.getArray("files");

        if (FileUtils.isBlank(url)) {
            call.reject("url is required");
            return;
        }
        final String urlValue = url.trim();
        final String tokenValue = token != null ? token.trim() : "";
        final String uploadKey = FileUtils.isBlank(fileKey) ? "files[]" : fileKey.trim();

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
                    call.reject("Invalid or missing 'path' for file at index " + i);
                    return;
                }

                String resolvedPath = FileUtils.resolveNativePath(context, filePathValue);
                if (FileUtils.isBlank(resolvedPath)) {
                    call.reject("Unable to resolve file path at index " + i + ": " + filePathValue);
                    return;
                }

                File file = new File(resolvedPath);
                if (!file.exists()) {
                    call.reject("File does not exist at index " + i + ": " + resolvedPath);
                    return;
                }

                String fileNameUpload = file.getName().trim();
                String mimeType = FileUtils.getMimeTypeFromFileName(fileNameUpload);
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
                appendFormData(requestBody, data);
            }
        } catch (Exception e) {
            call.reject("Failed to build upload request: " + e.getMessage(), e);
            return;
        }

        executeUpload(call, urlValue, tokenValue, requestBody.build());
    }

    private void appendFormData(MultipartBody.Builder requestBody, JSObject data) {
        Iterator<String> keys = data.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            try {
                Object value = data.get(key);
                if (value instanceof JSONObject || value instanceof JSONArray) {
                    requestBody.addFormDataPart(key, value.toString());
                } else if (value != null) {
                    requestBody.addFormDataPart(key, String.valueOf(value));
                }
            } catch (JSONException ignored) {
            }
        }
    }

    private void executeUpload(PluginCall call, String url, String token, MultipartBody postBody) {
        Request.Builder requestBuilder = new Request.Builder()
            .url(url)
            .post(postBody);

        if (!token.isEmpty()) {
            requestBuilder.header("Authorization", "Bearer " + token);
        }

        Request request = requestBuilder.build();

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
}
