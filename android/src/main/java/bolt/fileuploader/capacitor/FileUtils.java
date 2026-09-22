package bolt.fileuploader.capacitor;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
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

    /**
     * Attempts to resolve a {@code content://} URI to a real filesystem path via the
     * deprecated {@link MediaStore.MediaColumns#DATA} column.
     *
     * <p><b>Compatibility note:</b> The {@code DATA} column is reliable only on
     * Android 9 (API 28) and below. From API 29 onward, scoped storage means files in
     * shared storage may not have an accessible physical path even when the column is
     * populated. This method should therefore only be called on API &le; 28; prefer
     * {@link #copyContentUriToCache(Context, Uri)} on newer devices.
     *
     * @return absolute path string, or {@code null} if not resolvable.
     */
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

    /**
     * Copies the content addressed by a {@code content://} URI into the app's internal
     * cache directory and returns the resulting {@link File}.
     *
     * <p>This is the preferred resolution strategy on Android 10+ (API 29+) where scoped
     * storage makes direct filesystem paths unreliable. The copied file is served through
     * {@link androidx.core.content.FileProvider} when sharing with other apps.
     *
     * @return the cached {@link File}, or {@code null} if the copy failed.
     */
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

    /**
     * Resolves a path string (which may be a {@code file://} URI, a {@code content://}
     * URI, or a raw filesystem path) to an absolute filesystem path that can be opened
     * with {@link java.io.File}.
     *
     * <h3>Resolution strategy for {@code content://} URIs</h3>
     * <ul>
     *   <li><b>API &le; 28</b>: First tries the {@link MediaStore.MediaColumns#DATA}
     *       column for a direct path. Falls back to
     *       {@link #copyContentUriToCache(Context, Uri)} if the column is absent or
     *       returns null.</li>
     *   <li><b>API 29+</b>: Scoped storage makes the {@code DATA} column unreliable —
     *       goes straight to {@link #copyContentUriToCache(Context, Uri)} to avoid
     *       reading a path that may not be accessible.</li>
     * </ul>
     *
     * @param path a {@code file://} URI, {@code content://} URI, or raw path string.
     * @return resolved absolute path, or {@code null} if resolution fails.
     */
    public static String resolveNativePath(Context context, String path) throws Exception {
        if (isBlank(path)) {
            return null;
        }

        Uri uri = Uri.parse(path);
        String scheme = uri.getScheme();
        String resolvedPath;

        if (scheme != null && "file".equals(scheme.toLowerCase(Locale.ROOT))) {
            // file:// URI — decode directly to a filesystem path.
            resolvedPath = uri.getPath() != null ? uri.getPath() : path;
        } else if (scheme != null && "content".equals(scheme.toLowerCase(Locale.ROOT))) {
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                // API ≤ 28: attempt direct path via MediaStore.DATA first.
                // This avoids unnecessary cache copies on older devices where the column
                // is reliably populated and the path is directly accessible.
                String direct = resolveContentUriToPath(context, uri);
                if (direct != null) {
                    resolvedPath = direct;
                } else {
                    File copied = copyContentUriToCache(context, uri);
                    resolvedPath = copied != null ? copied.getAbsolutePath() : null;
                }
            } else {
                // API 29+: scoped storage — skip the DATA column and copy to cache
                // immediately. The DATA column may return a path that belongs to another
                // app's sandbox and is inaccessible even with READ_EXTERNAL_STORAGE.
                File copied = copyContentUriToCache(context, uri);
                resolvedPath = copied != null ? copied.getAbsolutePath() : null;
            }
        } else {
            // Raw filesystem path (no scheme).
            resolvedPath = path;
        }

        return isBlank(resolvedPath) ? null : resolvedPath;
    }
}
