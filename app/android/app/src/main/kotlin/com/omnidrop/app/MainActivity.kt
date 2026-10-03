package com.omnidrop.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.util.Size
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone


private const val CHANNEL = "com.omnidrop.app/localsend"
private const val REQUEST_CODE_PICK_DIRECTORY = 1
private const val REQUEST_CODE_PICK_DIRECTORY_PATH = 2
private const val REQUEST_CODE_PICK_FILE = 3
private const val REQUEST_CODE_LOCAL_NETWORK = 4
private const val REQUEST_CODE_PICK_FOLDER_TREE = 5
private const val REQUEST_CODE_PICK_STORAGE_TREE = 6

// Not available as a constant in compileSdk 36.
private const val PERMISSION_ACCESS_LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"
private const val API_LEVEL_ANDROID_17 = 37

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingStorageLocation = "internal"
    private var pendingStoragePickerForSetting = false

    /// share_handler drops share intents arriving via onNewIntent while the Dart side
    /// is not subscribed to its media stream yet, which happens when this singleTask
    /// activity is relaunched into an existing task while the app is still starting.
    /// Hold such intents back until Dart reports readiness ("shareIntentReady"), then
    /// replay them through the regular plugin path.
    private val pendingShareIntents = mutableListOf<Intent>()
    private var shareIntentReady = false

    override fun onNewIntent(intent: Intent) {
        if (!shareIntentReady && (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE)) {
            pendingShareIntents.add(intent)
            return
        }
        super.onNewIntent(intent)
    }

    private fun onShareIntentReady() {
        shareIntentReady = true
        val pending = pendingShareIntents.toList()
        pendingShareIntents.clear()
        for (intent in pending) {
            super.onNewIntent(intent)
        }
    }

    // Overriding the static methods we need from the Java class, as described
    // in the documentation of `FlutterActivity.NewEngineIntentBuilder`
    companion object {
        fun withNewEngine(): NewEngineIntentBuilder {
            return NewEngineIntentBuilder(MainActivity::class.java)
        }

        fun createDefaultIntent(launchContext: Context): Intent {
            return withNewEngine().build(launchContext)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    pendingResult = result
                    openDirectoryPicker(onlyPath = false)
                }

                "pickFiles" -> {
                    pendingResult = result
                    openFilePicker()
                }

                "pickDirectoryPath" -> {
                    pendingResult = result
                    openDirectoryPicker(onlyPath = true)
                }

                "pickFolderTree" -> {
                    pendingResult = result
                    pendingStorageLocation = "internal"
                    pendingStoragePickerForSetting = false
                    openStorageTreePicker("internal")
                }

                "pickStorageTree" -> {
                    pendingResult = result
                    val storage = call.argument<String>("storage") ?: "internal"
                    pendingStoragePickerForSetting = false
                    openStorageTreePicker(storage)
                }

                "getStorageTree" -> {
                    val storage = call.argument<String>("storage") ?: "internal"
                    result.success(getStorageTree(storage)?.toString())
                }

                "hasRemovableStorage" -> result.success(hasRemovableStorage())

                "getSaveLocation" -> {
                    val preferences = getSharedPreferences("storage", MODE_PRIVATE)
                    val location = preferences.getString("save_location", "internal") ?: "internal"
                    if (location == "sd" && !hasRemovableStorage()) {
                        preferences.edit().putString("save_location", "internal").apply()
                        result.success("internal")
                    } else {
                        result.success(location)
                    }
                }

                "setSaveLocation" -> {
                    val storage = call.argument<String>("storage") ?: "internal"
                    if (storage == "sd" && !hasRemovableStorage()) {
                        result.success(false)
                    } else {
                        val tree = getStorageTree(storage)
                        if (tree != null) {
                            getSharedPreferences("storage", MODE_PRIVATE).edit().putString("save_location", storage).apply()
                            result.success(true)
                        } else {
                            pendingResult = result
                            pendingStoragePickerForSetting = true
                            openStorageTreePicker(storage)
                        }
                    }
                }

                "listFolderTree" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) result.error("INVALID_ARGUMENT", "Missing folder URI", null)
                    else result.success(listTreeEntries(Uri.parse(uri)))
                }

                "listFolderTreeFiles" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) result.error("INVALID_ARGUMENT", "Missing folder URI", null)
                    else result.success(listTreeFiles(Uri.parse(uri), ""))
                }

                "createDirectory" -> handleCreateDirectory(call, result)

                "getFileDescriptor" -> handleGetFileDescriptor(call, result)

                "createFile" -> handleCreateFile(call, result)

                "copyFileToTree" -> handleCopyFileToTree(call, result)

                "openFileForWriting" -> handleOpenFileForWriting(call, result)

                "openContentUri" -> {
                    openUri(context, call.argument<String>("uri")!!)
                    result.success(null)
                }

                "openGallery" -> {
                    openGallery()
                    result.success(null)
                }

                "openWifiSettings" -> {
                    startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                    result.success(null)
                }

                "openAppNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    startActivity(intent)
                    result.success(null)
                }

                "openAppPermissionsSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(Uri.fromParts("package", packageName, null))
                    startActivity(intent)
                    result.success(null)
                }

                "shareInstalledApk" -> result.success(shareInstalledApk())

                "shareTextInvite" -> {
                    shareTextInvite()
                    result.success(null)
                }

                "shareIntentReady" -> {
                    onShareIntentReady()
                    result.success(null)
                }

                "isAnimationsEnabled" -> {
                    result.success(isAnimationsEnabled())
                }

                "getDownloadsDirectory" -> {
                    result.success(getDownloadsDirectory())
                }

                "queryMediaFiles" -> {
                    try {
                        result.success(queryMediaFiles(call.argument<String>("category") ?: "downloads"))
                    } catch (e: SecurityException) {
                        result.error("PERMISSION_DENIED", e.message ?: "Media access was denied", null)
                    }
                }

                "loadMediaThumbnail" -> {
                    val uri = call.argument<String>("uri")
                    val category = call.argument<String>("category")
                    if (uri == null || category == null) result.error("INVALID_ARGUMENT", "Missing URI or category", null)
                    else result.success(loadMediaThumbnail(Uri.parse(uri), category))
                }

                "requestLocalNetworkPermission" -> {
                    if (hasLocalNetworkPermission()) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        requestPermissions(arrayOf(PERMISSION_ACCESS_LOCAL_NETWORK), REQUEST_CODE_LOCAL_NETWORK)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun shareInstalledApk(): Boolean {
        return try {
            val apk = File(applicationInfo.sourceDir)
            if (!apk.canRead()) return false
            val sharedApk = File(cacheDir, "share/OmniDrop.apk")
            sharedApk.parentFile?.mkdirs()
            apk.copyTo(sharedApk, overwrite = true)
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", sharedApk)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.android.package-archive"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Share OmniDrop"))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun shareTextInvite() {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "Install OmniDrop for private local file sharing: https://omnidrop.app")
        }
        startActivity(Intent.createChooser(intent, "Share OmniDrop"))
    }

    /// Android 17+ gates local network access behind a runtime permission; older versions grant it implicitly.
    private fun hasLocalNetworkPermission(): Boolean {
        if (Build.VERSION.SDK_INT < API_LEVEL_ANDROID_17) {
            return true
        }
        return checkSelfPermission(PERMISSION_ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_LOCAL_NETWORK) {
            pendingPermissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermissionResult = null
        }
    }

    /// Absolute path of the shared "Download" directory (usually /storage/emulated/0/Download).
    @Suppress("DEPRECATION")
    private fun getDownloadsDirectory(): String {
        return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
    }

    private fun queryMediaFiles(category: String): List<Map<String, Any?>> {
        val documents = category == "documents"
        val collection = when (category) {
            "images" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "videos" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            "downloads" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Files.getContentUri("external")
            }
            else -> MediaStore.Files.getContentUri("external")
        }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        val supportedMimeTypes = arrayOf(
            "application/pdf",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "text/plain",
            "text/csv",
            "application/epub+zip",
            "application/zip",
        )
        val selection = when {
            documents -> "${MediaStore.MediaColumns.MIME_TYPE} IN (${supportedMimeTypes.joinToString(",") { "?" }})"
            category == "downloads" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
            category == "downloads" -> "${MediaStore.MediaColumns.DATA} LIKE ?"
            else -> null
        }
        val selectionArgs = when {
            documents -> supportedMimeTypes
            category == "downloads" -> arrayOf(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "Download/%" else "${getDownloadsDirectory()}%")
            else -> null
        }
        val sortOrder = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
        val files = mutableListOf<Map<String, Any?>>()
        val cursor = contentResolver.query(collection, projection, selection, selectionArgs, sortOrder) ?: return files
        cursor.use {
            val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            while (it.moveToNext()) {
                val id = it.getLong(idColumn)
                val modified = it.getLong(modifiedColumn)
                files.add(
                    FileInfo(
                        name = it.getString(nameColumn) ?: "",
                        size = it.getLong(sizeColumn).coerceAtLeast(0),
                        uri = ContentUris.withAppendedId(collection, id).toString(),
                        lastModified = if (modified > 0) Date(modified * 1000).time.toRfc3339() else null,
                    ).toMap(),
                )
            }
        }
        return files
    }

    @Suppress("DEPRECATION")
    private fun loadMediaThumbnail(uri: Uri, category: String): ByteArray? {
        return try {
            val bitmap = when {
                category == "audio" -> {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(this, uri)
                        val embeddedArt = retriever.embeddedPicture ?: return null
                        decodeEmbeddedArtwork(embeddedArt)
                    } finally {
                        retriever.release()
                    }
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> contentResolver.loadThumbnail(uri, Size(256, 256), null)
                category == "images" -> MediaStore.Images.Thumbnails.getThumbnail(
                    contentResolver,
                    ContentUris.parseId(uri),
                    MediaStore.Images.Thumbnails.MINI_KIND,
                    null,
                )
                category == "videos" -> MediaStore.Video.Thumbnails.getThumbnail(
                    contentResolver,
                    ContentUris.parseId(uri),
                    MediaStore.Video.Thumbnails.MINI_KIND,
                    null,
                )
                else -> null
            } ?: return null
            ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 78, output)
                bitmap.recycle()
                output.toByteArray()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun hasRemovableStorage(): Boolean {
        val storageManager = getSystemService(Context.STORAGE_SERVICE) as StorageManager
        return storageManager.storageVolumes.any { it.isRemovable && it.state == Environment.MEDIA_MOUNTED }
    }

    private fun decodeEmbeddedArtwork(data: ByteArray): Bitmap? {
        val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        var sampleSize = 1
        while (bounds.outWidth / sampleSize > 256 || bounds.outHeight / sampleSize > 256) {
            sampleSize *= 2
        }
        return android.graphics.BitmapFactory.decodeByteArray(
            data,
            0,
            data.size,
            android.graphics.BitmapFactory.Options().apply { inSampleSize = sampleSize },
        )
    }

    private fun getStorageTree(storage: String): Uri? {
        val preferences = getSharedPreferences("storage", MODE_PRIVATE)
        val key = if (storage == "sd") "tree_sd" else "tree_internal"
        val saved = preferences.getString(key, null)?.let(Uri::parse)
        if (saved != null && contentResolver.persistedUriPermissions.any { it.uri == saved && it.isReadPermission && it.isWritePermission }) {
            ensureOmniDropFolders(saved)
            return saved
        }
        if (saved != null) preferences.edit().remove(key).apply()

        val externalTree = contentResolver.persistedUriPermissions.firstOrNull { permission ->
            if (!permission.isReadPermission || !permission.isWritePermission) return@firstOrNull false
            val id = runCatching { DocumentsContract.getTreeDocumentId(permission.uri) }.getOrNull() ?: return@firstOrNull false
            if (storage == "sd") id.substringBefore(':') != "primary" else id.substringBefore(':') == "primary"
        }?.uri ?: return null
        preferences.edit().putString(key, externalTree.toString()).apply()
        ensureOmniDropFolders(externalTree)
        return externalTree
    }

    private fun ensureOmniDropFolders(treeUri: Uri) {
        val root = DocumentFile.fromTreeUri(this, treeUri) ?: throw IllegalStateException("Could not open storage tree")
        val omniDrop = root.findFile("OmniDrop")?.takeIf { it.isDirectory } ?: root.createDirectory("OmniDrop")
            ?: throw IllegalStateException("Could not create OmniDrop folder")
        for (name in listOf("image", "video", "audio", "app", "folder", "other")) {
            if (omniDrop.findFile(name)?.isDirectory != true && omniDrop.createDirectory(name) == null) {
                throw IllegalStateException("Could not create OmniDrop/$name folder")
            }
        }
    }

    private fun isAnimationsEnabled() : Boolean {
        return Settings.Global.getFloat(this.getContentResolver(),
            Settings.Global.ANIMATOR_DURATION_SCALE, 1.0f) != 0.0f;
    }

    private fun handleGetFileDescriptor(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "Missing content URI", null)
            return
        }

        val uri = Uri.parse(uriString)
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) {
            result.error("INVALID_ARGUMENT", "Expected a content:// URI", null)
            return
        }

        try {
            val parcelFileDescriptor = contentResolver.openFileDescriptor(uri, "r")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            // Ownership of the detached descriptor is transferred to the caller. It must be
            // closed by Rust (or whichever native consumer receives it) after use.
            parcelFileDescriptor.use {
                result.success(it.detachFd())
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "Failed to open content URI", null)
        }
    }

    /// Creates a new file inside a SAF directory and opens it for writing.
    ///
    /// Returns the URI of the created document (Android may rename the file on
    /// collisions) and an owned writable file descriptor. The descriptor must be
    /// closed by the native consumer it is passed to.
    private fun handleCreateFile(call: MethodCall, result: MethodChannel.Result) {
        val parentUriString = call.argument<String>("parentUri")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (parentUriString == null || fileName == null) {
            result.error("INVALID_ARGUMENT", "Missing parentUri or fileName", null)
            return
        }

        try {
            val parentUri = Uri.parse(parentUriString)

            // A pure tree URI (content://…/tree/X) must be converted to its
            // document form before it can be used as a parent document.
            val segments = parentUri.pathSegments
            val parentDocumentUri = if (segments.size == 2 && segments[0] == "tree") {
                DocumentsContract.buildDocumentUriUsingTree(
                    parentUri,
                    DocumentsContract.getTreeDocumentId(parentUri)
                )
            } else {
                parentUri
            }

            val parent = findTreeDocument(parentDocumentUri)
            val documentUri = parent?.createFile(mimeType, fileName)?.uri
            if (documentUri == null) {
                result.error("CREATE_FAILED", "Could not create $fileName in $parentUriString", null)
                return
            }

            // "wt" is write + truncate: the document is new, unless the provider
            // handed out an existing one instead of creating a second document.
            val parcelFileDescriptor = contentResolver.openFileDescriptor(documentUri, "wt")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            parcelFileDescriptor.use {
                result.success(
                    mapOf(
                        "uri" to documentUri.toString(),
                        "fd" to it.detachFd(),
                    )
                )
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("CREATE_FAILED", e.message ?: "Failed to create file", null)
        }
    }

    /// Opens an existing document created by [handleCreateFile] for writing,
    /// discarding its current content.
    ///
    /// Used to write a file again after a failed attempt, so that it keeps its
    /// name instead of being created a second time under a numbered one.
    ///
    /// Returns an owned writable file descriptor. It stays open after this call
    /// and must be closed by the native consumer it is passed to.
    private fun handleOpenFileForWriting(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "Missing content URI", null)
            return
        }

        val uri = Uri.parse(uriString)
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) {
            result.error("INVALID_ARGUMENT", "Expected a content:// URI", null)
            return
        }

        try {
            // "wt" is write + truncate. A document provider may ignore the
            // truncation, so the writer additionally shortens the file itself.
            val parcelFileDescriptor = contentResolver.openFileDescriptor(uri, "wt")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            parcelFileDescriptor.use {
                result.success(it.detachFd())
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "Failed to open content URI", null)
        }
    }

    private fun handleCopyFileToTree(call: MethodCall, result: MethodChannel.Result) {
        val parentUri = call.argument<String>("parentUri")?.let(Uri::parse)
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (parentUri == null || sourcePath == null || fileName == null) {
            result.error("INVALID_ARGUMENT", "Missing parentUri, sourcePath, or fileName", null)
            return
        }

        try {
            val parent = findTreeDocument(parentUri) ?: throw IllegalStateException("Could not find the destination folder")
            val documentUri = parent.createFile(mimeType, fileName)?.uri ?: throw IllegalStateException("Could not create $fileName")
            val output = contentResolver.openOutputStream(documentUri, "wt")
                ?: throw IllegalStateException("Could not open $fileName for writing")
            FileInputStream(sourcePath).use { input -> output.use { input.copyTo(it) } }
            result.success(documentUri.toString())
        } catch (e: Exception) {
            result.error("COPY_FAILED", e.message ?: "Could not copy file to storage", null)
        }
    }

    private fun openDirectoryPicker(onlyPath: Boolean) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        startActivityForResult(
            intent,
            if (onlyPath) REQUEST_CODE_PICK_DIRECTORY_PATH else REQUEST_CODE_PICK_DIRECTORY
        )
    }

    private fun openFolderTreePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_FOLDER_TREE)
    }

    private fun openStorageTreePicker(storage: String) {
        pendingStorageLocation = storage
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val initialUri = if (storage == "sd") {
                    val volume = (getSystemService(Context.STORAGE_SERVICE) as StorageManager).storageVolumes
                        .firstOrNull { it.isRemovable && it.state == Environment.MEDIA_MOUNTED }
                    volume?.uuid?.let { Uri.parse("content://com.android.externalstorage.documents/root/$it") }
                } else {
                    Uri.parse("content://com.android.externalstorage.documents/root/primary")
                }
                if (initialUri != null) putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
            }
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_STORAGE_TREE)
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra("multi-pick", true)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_FILE)
    }

    @SuppressLint("WrongConstant")
    @Override
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode == Activity.RESULT_CANCELED) {
            if (requestCode == REQUEST_CODE_PICK_FOLDER_TREE || requestCode == REQUEST_CODE_PICK_STORAGE_TREE) {
                if (requestCode == REQUEST_CODE_PICK_STORAGE_TREE && pendingStoragePickerForSetting) pendingResult?.success(false)
                else pendingResult?.success(null)
            } else {
                pendingResult?.error("CANCELED", "Canceled", null)
            }
            pendingResult = null
            return
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult?.error("Error $resultCode", "Failed to access directory or file", null)
            pendingResult = null
            return
        }

        when (requestCode) {
            REQUEST_CODE_PICK_DIRECTORY -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)

                    val files = mutableListOf<FileInfo>()
                    listFiles(uri, files)
                    val resultData = PickDirectoryResult(uri.toString(), files)
                    pendingResult?.success(resultData.toMap())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_DIRECTORY_PATH -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    pendingResult?.success(uri.toString())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_FOLDER_TREE -> {
                val uri = data.data
                val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    getSharedPreferences("storage", MODE_PRIVATE).edit().putString("tree_internal", uri.toString()).apply()
                    ensureOmniDropFolders(uri)
                    pendingResult?.success(uri.toString())
                } else {
                    pendingResult?.error("Error", "Failed to access folder", null)
                }
                pendingResult = null
            }

            REQUEST_CODE_PICK_STORAGE_TREE -> {
                val uri = data.data
                val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    try {
                        val storageId = runCatching { DocumentsContract.getTreeDocumentId(uri).substringBefore(':') }.getOrNull()
                        val externalStorageProvider = uri.authority == "com.android.externalstorage.documents"
                        val wrongVolume = !externalStorageProvider ||
                            pendingStorageLocation == "sd" && storageId == "primary" ||
                            pendingStorageLocation == "internal" && storageId != "primary"
                        if (wrongVolume) {
                            pendingResult?.success(if (pendingStoragePickerForSetting) false else null)
                            pendingResult = null
                            pendingStoragePickerForSetting = false
                            return
                        }
                        contentResolver.takePersistableUriPermission(uri, takeFlags)
                        ensureOmniDropFolders(uri)
                        val preferences = getSharedPreferences("storage", MODE_PRIVATE)
                        val treeKey = if (pendingStorageLocation == "sd") "tree_sd" else "tree_internal"
                        preferences.edit().putString(treeKey, uri.toString()).putString("save_location", pendingStorageLocation).apply()
                        pendingResult?.success(if (pendingStoragePickerForSetting) true else uri.toString())
                    } catch (e: Exception) {
                        pendingResult?.error("STORAGE_SETUP_FAILED", e.message ?: "Could not initialize storage", null)
                    }
                } else {
                    pendingResult?.success(false)
                }
                pendingResult = null
                pendingStoragePickerForSetting = false
            }

            REQUEST_CODE_PICK_FILE -> {
                val uriList: List<Uri> = when {
                    data.clipData != null -> {
                        val clipData = data.clipData
                        val uris = mutableListOf<Uri>()
                        for (i in 0 until clipData!!.itemCount) {
                            uris.add(clipData.getItemAt(i).uri)
                        }
                        uris
                    }

                    data.data != null -> listOf(data.data!!)
                    else -> {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                }

                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

                val resultList = mutableListOf<FileInfo>()
                for (uri in uriList) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    val documentFile = FastDocumentFile.fromDocumentUri(this, uri)
                    if (documentFile == null) {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                    resultList.add(
                        FileInfo(
                            name = documentFile.name,
                            size = documentFile.size,
                            uri = uri.toString(),
                            lastModified = documentFile.lastModified?.toRfc3339(),
                        )
                    )
                }

                pendingResult?.success(resultList.map { it.toMap() })
                pendingResult = null
            }
        }
    }

    private fun listFiles(uri: Uri, files: MutableList<FileInfo>) {
        val pickedDir: FastDocumentFile = FastDocumentFile.fromTreeUri(this, uri)

        for (file in pickedDir.listFiles()) {
            if (file.isDirectory) {
                // Recursive call
                listFiles(file.uri, files)
            } else if (file.isFile) {
                files.add(
                    FileInfo(
                        name = file.name,
                        size = file.size,
                        uri = file.uri.toString(),
                        lastModified = file.lastModified?.toRfc3339(),
                    ),
                )
            }
        }
    }

    private fun listTreeEntries(uri: Uri): List<Map<String, Any?>> {
        val root = findTreeDocument(uri) ?: return emptyList()
        return root.listFiles().map { entry ->
            mapOf(
                "name" to (entry.name ?: ""),
                "size" to entry.length().coerceAtLeast(0L),
                "uri" to entry.uri.toString(),
                "lastModified" to entry.lastModified().takeIf { it > 0L }?.toRfc3339(),
                "isDirectory" to entry.isDirectory,
            )
        }
    }

    private fun listTreeFiles(uri: Uri, parentPath: String): List<Map<String, Any?>> {
        val root = findTreeDocument(uri) ?: return emptyList()
        return listDocumentFiles(root, parentPath)
    }

    private fun listDocumentFiles(parent: DocumentFile, parentPath: String): List<Map<String, Any?>> {
        val files = mutableListOf<Map<String, Any?>>()
        for (entry in parent.listFiles()) {
            val name = entry.name ?: ""
            val relativePath = if (parentPath.isEmpty()) name else "$parentPath/$name"
            if (entry.isDirectory) {
                files.addAll(listDocumentFiles(entry, relativePath))
            } else if (entry.isFile && name.isNotEmpty()) {
                files.add(
                    FileInfo(
                        name = relativePath,
                        size = entry.length().coerceAtLeast(0L),
                        uri = entry.uri.toString(),
                        lastModified = entry.lastModified().takeIf { it > 0L }?.toRfc3339(),
                    ).toMap(),
                )
            }
        }
        return files
    }

    private fun handleCreateDirectory(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = Uri.parse(call.argument<String>("documentUri")!!)
        val directoryName = call.argument<String>("directoryName")!!
        try {
            val parent = findTreeDocument(documentUri) ?: throw IllegalStateException("Could not find the parent folder")
            val existing = parent.findFile(directoryName)
            if (existing?.isDirectory == true || parent.createDirectory(directoryName) != null) {
                result.success(null)
            } else {
                result.error("CREATE_FAILED", "Could not create folder $directoryName", null)
            }
        } catch (e: Exception) {
            result.error("CREATE_FAILED", e.message ?: "Could not create folder", null)
        }
    }

    private fun findTreeDocument(uri: Uri): DocumentFile? {
        val treeUri = Uri.parse(uri.toString().substringBefore("/document/"))
        val treeDocumentId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull() ?: return null
        val targetDocumentId = if (DocumentsContract.isDocumentUri(this, uri)) {
            DocumentsContract.getDocumentId(uri)
        } else {
            treeDocumentId
        }
        if (targetDocumentId != treeDocumentId && !targetDocumentId.startsWith("$treeDocumentId/")) return null

        var current = DocumentFile.fromTreeUri(this, treeUri) ?: return null
        val relativePath = targetDocumentId.removePrefix(treeDocumentId).trimStart('/')
        for (name in relativePath.split('/').filter { it.isNotEmpty() }) {
            current = current.findFile(name) ?: return null
        }
        return current
    }

    private fun openGallery() {
        val intent = Intent()
        intent.action = Intent.ACTION_VIEW
        intent.type = "image/*"
        startActivity(intent)
    }
}

data class PickDirectoryResult(
    val directoryUri: String,
    val files: List<FileInfo>,
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "directoryUri" to directoryUri,
            "files" to files.map { it.toMap() }
        )
    }
}

data class FileInfo(
    val name: String,
    val size: Long,
    val uri: String,
    val lastModified: String?
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "name" to name,
            "size" to size,
            "uri" to uri,
            "lastModified" to lastModified
        )
    }
}

/// Formats milliseconds since epoch as an RFC 3339 string in UTC.
private fun Long.toRfc3339(): String {
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    format.timeZone = TimeZone.getTimeZone("UTC")
    return format.format(Date(this))
}
