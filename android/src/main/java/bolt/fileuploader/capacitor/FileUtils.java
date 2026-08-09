package bolt.fileuploader.capacitor;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.URI;
import java.util.Locale;

public class FileUtils {

    public static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    public static File getFileFromUriString(String filePath) {
        return filePath.startsWith("file://") ? new File(URI.create(filePath)) : new File(filePath);
    }

    public static String getMimeTypeFromFileName(String fileName) {
        if (isBlank(fileName) || !fileName.contains(".")) {
            return null;
        }
        int extIndex = fileName.lastIndexOf('.') + 1;
        String extension = fileName.substring(extIndex).toLowerCase(Locale.ROOT);
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
    }

    public static String resolveContentUriToPath(Context context, Uri uri) {
        String[] projection = new String[]{MediaStore.MediaColumns.DATA};
        Cursor cursor = null;
        try {
            cursor = context.getContentResolver().query(uri, projection, null, null, null);
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

    public static File copyContentUriToCache(Context context, Uri uri) {
        InputStream inputStream = null;
        try {
            inputStream = context.getContentResolver().openInputStream(uri);
            if (inputStream == null) {
                return null;
            }

            String fileName = queryDisplayName(context, uri);
            if (fileName == null) {
                fileName = "upload_" + System.currentTimeMillis();
            }
            String safeName = fileName.replaceAll("[^a-zA-Z0-9._-]", "_");
            File outputFile = new File(context.getCacheDir(), safeName);

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

    public static String queryDisplayName(Context context, Uri uri) {
        Cursor cursor = null;
        try {
            cursor = context.getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null);
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

    public static String resolveNativePath(Context context, String path) throws Exception {
        if (isBlank(path)) {
            return null;
        }

        Uri uri = Uri.parse(path);
        String scheme = uri.getScheme();
        String resolvedPath;
        if (scheme != null && "file".equals(scheme.toLowerCase(Locale.ROOT))) {
            resolvedPath = uri.getPath() != null ? uri.getPath() : path;
        } else if (scheme != null && "content".equals(scheme.toLowerCase(Locale.ROOT))) {
            String direct = resolveContentUriToPath(context, uri);
            if (direct != null) {
                resolvedPath = direct;
            } else {
                File copied = copyContentUriToCache(context, uri);
                resolvedPath = copied != null ? copied.getAbsolutePath() : null;
            }
        } else {
            resolvedPath = path;
        }

        return isBlank(resolvedPath) ? null : resolvedPath;
    }
}
