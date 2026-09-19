package bolt.fileuploader.capacitor;

import android.content.Context;
import android.os.Environment;
import android.util.Log;

import com.androidnetworking.AndroidNetworking;
import com.androidnetworking.common.Priority;
import com.androidnetworking.error.ANError;
import com.androidnetworking.interfaces.DownloadListener;
import com.androidnetworking.interfaces.DownloadProgressListener;
import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;

import java.io.File;

public class FileDownloadManager {

    /**
     * JavaScript's Number type is IEEE-754 double-precision, which can represent
     * integers exactly only up to 2^53 (Number.MAX_SAFE_INTEGER = 9,007,199,254,740,991).
     * Files larger than ~8 PiB would produce precision loss; we clamp and log if that occurs.
     */
    private static final long JS_MAX_SAFE_INTEGER = 9_007_199_254_740_991L;

    private static long safeProgressValue(long value, String label) {
        if (value > JS_MAX_SAFE_INTEGER) {
            Log.w("FileUpload", "safeProgressValue: '" + label + "'=" + value
                + " exceeds JS Number.MAX_SAFE_INTEGER (" + JS_MAX_SAFE_INTEGER
                + "). Clamping to avoid precision loss in the JavaScript layer.");
            return JS_MAX_SAFE_INTEGER;
        }
        return value;
    }

    public interface EventNotifier {
        void notify(String eventName, JSObject data);
    }

    public static void startDownloadFile(Context context, PluginCall call, EventNotifier notifier) {
        String path = call.getString("path");
        String fileName = call.getString("name");

        if (FileUtils.isBlank(path)) {
            call.reject("path is required");
            return;
        }
        if (FileUtils.isBlank(fileName)) {
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
        if (notifier != null) {
            notifier.notify("downloadStatus", start);
        }

        AndroidNetworking.initialize(context.getApplicationContext());

        File targetDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        if (targetDir == null || (!targetDir.exists() && !targetDir.mkdirs()) || !targetDir.canWrite()) {
            File externalDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
            if (externalDir != null) {
                targetDir = externalDir;
            } else {
                targetDir = context.getFilesDir();
            }
        }

        String downloadDir = targetDir.getAbsolutePath();
        String downloadPath = downloadDir + "/" + fileNameValue;

        AndroidNetworking.download(pathValue, downloadDir, fileNameValue)
            .setTag("Downloading - " + fileNameValue)
            .setPriority(Priority.MEDIUM)
            .setPercentageThresholdForCancelling(50)
            .build()
            .setDownloadProgressListener(
                (DownloadProgressListener) (bytesDownloaded, totalBytes) -> {
                    // FIX: Clamp long values to JS Number.MAX_SAFE_INTEGER to prevent
                    // silent precision loss when the Capacitor bridge serializes to JS.
                    long safeDownloaded = safeProgressValue(bytesDownloaded, "bytesDownloaded");
                    long safeTotal = safeProgressValue(totalBytes, "totalBytes");

                    JSObject progress = new JSObject();
                    progress.put("path", "file://" + downloadPath);
                    progress.put("start", false);
                    progress.put("finish", false);
                    progress.put("error", false);
                    progress.put("bytesDownloaded", safeDownloaded);
                    progress.put("totalBytes", safeTotal);
                    if (notifier != null) {
                        notifier.notify("downloadStatus", progress);
                    }
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
                        if (notifier != null) {
                            notifier.notify("downloadStatus", finish);
                        }

                        JSObject result = new JSObject();
                        result.put("path", "file://" + downloadPath);
                        result.put("error", false);
                        result.put("status", true);
                        call.resolve(result);
                    }

                    @Override
                    public void onError(ANError error) {
                        Log.d("FileUpload", "download error: " + (error != null ? error.getErrorDetail() : "unknown"));

                        JSObject finish = new JSObject();
                        finish.put("path", "file://" + downloadPath);
                        finish.put("start", false);
                        finish.put("finish", false);
                        finish.put("error", true);
                        if (notifier != null) {
                            notifier.notify("downloadStatus", finish);
                        }

                        JSObject result = new JSObject();
                        result.put("path", "file://" + downloadPath);
                        result.put("error", true);
                        result.put("status", false);
                        result.put("message", error != null ? error.getErrorDetail() : "Download error");
                        call.resolve(result);
                    }
                }
            );
    }
}
