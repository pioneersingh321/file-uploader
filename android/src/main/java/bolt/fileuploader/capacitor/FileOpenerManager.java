package bolt.fileuploader.capacitor;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Environment;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;

import java.io.File;

public class FileOpenerManager {

    public static void openFile(Context context, PluginCall call) {
        String filePath = call.getString("path");
        String fileType = call.getString("type", "application/pdf");

        if (FileUtils.isBlank(filePath)) {
            call.reject("path is required");
            return;
        }
        String filePathValue = filePath.trim();
        String fileTypeValue = FileUtils.isBlank(fileType) ? "application/pdf" : fileType.trim();

        File downloadFile = new File(filePathValue.replace("file://", ""));
        if (!downloadFile.exists()) {
            String storage =
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).toString() +
                    "/" + downloadFile.getName();
            downloadFile = new File(storage);
        }

        if (!downloadFile.exists()) {
            JSObject result = new JSObject();
            result.put("status", false);
            result.put("error", true);
            result.put("message", "File not found");
            result.put("path", downloadFile.getAbsolutePath());
            call.resolve(result);
            return;
        }

        try {
            Uri pathUri = FileProvider.getUriForFile(
                context.getApplicationContext(),
                context.getApplicationContext().getPackageName() + ".fileprovider",
                downloadFile
            );
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(pathUri, fileTypeValue);
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            context.startActivity(intent);

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
}
