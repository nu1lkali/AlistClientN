package com.github.alist.activity

import android.content.ContentValues
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.exifinterface.media.ExifInterface
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import com.github.chrisbanes.photoview.PhotoView
import com.github.alist.bean.VideoItem
import com.github.alist.client.R
import com.github.alist.utils.FlutterMethods
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

class HeicViewerActivity : AppCompatActivity() {

    private lateinit var viewPager: ViewPager2
    private lateinit var tvTitle: TextView
    private lateinit var tvIndex: TextView
    private lateinit var btnFavorite: ImageButton
    private lateinit var btnSlideshow: ImageButton
    private lateinit var adapter: HeicPagerAdapter

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var names: ArrayList<String> = arrayListOf()
    private var urls: ArrayList<String> = arrayListOf()
    private var localPaths: ArrayList<String> = arrayListOf()
    private var remotePaths: ArrayList<String> = arrayListOf()
    private var signs: ArrayList<String> = arrayListOf()
    private var sizes: ArrayList<String> = arrayListOf()
    private var initialIndex: Int = 0
    private var currentIndex: Int = 0
    private var screenLongEdge: Int = 2048

    // 幻灯片
    private var slideshowActive = false
    private val slideshowHandler = Handler(Looper.getMainLooper())
    private val slideshowRunnable = object : Runnable {
        override fun run() {
            if (!slideshowActive || urls.isEmpty()) return
            val next = (currentIndex + 1) % urls.size
            viewPager.setCurrentItem(next, true)
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val seconds = prefs.getLong("flutter.slideshowIntervalSeconds", 3L).toInt().coerceIn(1, 60)
            slideshowHandler.postDelayed(this, seconds * 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.statusBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        setContentView(R.layout.activity_heic_viewer)

        @Suppress("DEPRECATION")
        val dm = DisplayMetrics().also { windowManager.defaultDisplay.getMetrics(it) }
        screenLongEdge = maxOf(dm.widthPixels, dm.heightPixels)

        names = intent.getStringArrayListExtra("names") ?: arrayListOf()
        urls = intent.getStringArrayListExtra("urls") ?: arrayListOf()
        localPaths = intent.getStringArrayListExtra("localPaths") ?: arrayListOf()
        remotePaths = intent.getStringArrayListExtra("remotePaths") ?: arrayListOf()
        signs = intent.getStringArrayListExtra("signs") ?: arrayListOf()
        sizes = intent.getStringArrayListExtra("sizes") ?: arrayListOf()
        initialIndex = intent.getIntExtra("index", 0).coerceIn(0, (urls.size - 1).coerceAtLeast(0))
        currentIndex = initialIndex

        viewPager = findViewById(R.id.view_pager)
        tvTitle = findViewById(R.id.tv_title)
        tvIndex = findViewById(R.id.tv_index)
        btnFavorite = findViewById(R.id.btn_favorite)
        btnSlideshow = findViewById(R.id.btn_slideshow)

        findViewById<View>(R.id.btn_back).setOnClickListener { finish() }
        btnSlideshow.setOnClickListener { toggleSlideshow() }
        findViewById<View>(R.id.btn_rotate).setOnClickListener { rotateCurrent() }
        btnFavorite.setOnClickListener { toggleFavorite() }
        findViewById<View>(R.id.btn_more).setOnClickListener { showMoreMenu(it) }

        adapter = HeicPagerAdapter(urls, localPaths, screenLongEdge, scope)
        viewPager.adapter = adapter
        viewPager.setCurrentItem(initialIndex, false)
        updateHeader(initialIndex)

        viewPager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                currentIndex = position
                updateHeader(position)
                checkFavoriteStatus()
            }
        })

        checkFavoriteStatus()
    }

    private fun updateHeader(index: Int) {
        tvTitle.text = names.getOrNull(index) ?: ""
        if (urls.size > 1) {
            tvIndex.text = "${index + 1} / ${urls.size}"
            tvIndex.visibility = View.VISIBLE
        } else {
            tvIndex.visibility = View.GONE
        }
    }

    // ── 幻灯片 ──────────────────────────────────────────────────────────────

    private fun toggleSlideshow() {
        slideshowActive = !slideshowActive
        if (slideshowActive) {
            btnSlideshow.setImageResource(R.drawable.ic_pause_circle_outline)
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val seconds = prefs.getLong("flutter.slideshowIntervalSeconds", 3L).toInt().coerceIn(1, 60)
            slideshowHandler.postDelayed(slideshowRunnable, seconds * 1000L)
        } else {
            btnSlideshow.setImageResource(R.drawable.ic_slideshow_rounded)
            slideshowHandler.removeCallbacks(slideshowRunnable)
        }
    }

    // ── 旋转 ────────────────────────────────────────────────────────────────

    private fun rotateCurrent() {
        adapter.rotatePage(currentIndex)
    }

    // ── 收藏 ────────────────────────────────────────────────────────────────

    private fun makeVideoItem(index: Int) = VideoItem(
        name = names.getOrNull(index) ?: "",
        localPath = localPaths.getOrNull(index)?.takeIf { it.isNotEmpty() },
        remotePath = remotePaths.getOrNull(index) ?: urls.getOrNull(index) ?: "",
        sign = signs.getOrNull(index)?.takeIf { it.isNotEmpty() },
        provider = null, thumb = null,
        url = urls.getOrNull(index) ?: "",
        modifiedMilliseconds = null,
        size = sizes.getOrNull(index)?.takeIf { it.isNotEmpty() }
    )

    private fun checkFavoriteStatus() {
        try {
            FlutterMethods.checkFavoriteStatus(makeVideoItem(currentIndex)) { isFavorite ->
                runOnUiThread { updateFavoriteIcon(isFavorite) }
            }
        } catch (_: Exception) {}
    }

    private fun toggleFavorite() {
        try {
            FlutterMethods.toggleFavorite(makeVideoItem(currentIndex)) { isFavorite ->
                runOnUiThread {
                    updateFavoriteIcon(isFavorite)
                    toast(if (isFavorite) "已添加到收藏" else "已取消收藏")
                }
            }
        } catch (_: Exception) { toast("操作失败") }
    }

    private fun updateFavoriteIcon(isFavorite: Boolean) {
        btnFavorite.setImageResource(
            if (isFavorite) R.drawable.ic_favorite_filled else R.drawable.ic_favorite
        )
        btnFavorite.imageTintList = null
    }

    // ── 三点菜单 ─────────────────────────────────────────────────────────────

    private fun showMoreMenu(anchor: View) {
        val popup = PopupMenu(this, anchor)
        popup.menu.add(0, 1, 0, "复制链接")
        popup.menu.add(0, 2, 1, "保存到相册")
        popup.menu.add(0, 3, 2, "图片信息")
        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> copyLink()
                2 -> saveToAlbum()
                3 -> showImageInfo()
            }
            true
        }
        popup.show()
    }

    private fun copyLink() {
        val url = urls.getOrNull(currentIndex)?.takeIf { it.isNotEmpty() } ?: run {
            toast("无法获取链接"); return
        }
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("link", url))
        toast("链接已复制")
    }

    private fun saveToAlbum() {
        val url = urls.getOrNull(currentIndex)?.takeIf { it.isNotEmpty() } ?: run {
            toast("无法获取下载链接"); return
        }
        val localPath = localPaths.getOrNull(currentIndex)?.takeIf { it.isNotEmpty() }
        val name = names.getOrNull(currentIndex) ?: "image.heic"

        scope.launch {
            toast("正在保存...")
            val success = withContext(Dispatchers.IO) {
                try {
                    // 优先用本地文件，否则下载
                    val sourceFile = if (localPath != null && File(localPath).exists()) {
                        File(localPath)
                    } else {
                        val cacheFile = File(cacheDir, "heic_${url.hashCode()}.heic")
                        if (!cacheFile.exists()) {
                            val resp = httpClient.newCall(Request.Builder().url(url).build()).execute()
                            if (!resp.isSuccessful) return@withContext false
                            FileOutputStream(cacheFile).use { it.write(resp.body!!.bytes()) }
                            resp.close()
                        }
                        cacheFile
                    }
                    saveFileToGallery(sourceFile, name)
                } catch (e: Exception) {
                    android.util.Log.e("HeicViewer", "saveToAlbum failed: $e")
                    false
                }
            }
            toast(if (success) "已保存到相册" else "保存失败")
        }
    }

    private fun saveFileToGallery(file: File, name: String): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/heic")
                put(MediaStore.Images.Media.RELATIVE_PATH, "DCIM/AListClient")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
            contentResolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            true
        } else {
            val dir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DCIM)
            val dest = File(File(dir, "AListClient").also { it.mkdirs() }, name)
            file.copyTo(dest, overwrite = true)
            // 通知媒体库扫描
            sendBroadcast(android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE,
                android.net.Uri.fromFile(dest)))
            true
        }
    }

    private fun showImageInfo() {
        val localPath = localPaths.getOrNull(currentIndex)?.takeIf { it.isNotEmpty() }
        val url = urls.getOrNull(currentIndex) ?: ""
        val name = names.getOrNull(currentIndex) ?: ""
        val size = sizes.getOrNull(currentIndex) ?: ""
        scope.launch {
            val text = withContext(Dispatchers.IO) { buildExifText(localPath, url, name, size) }
            AlertDialog.Builder(this@HeicViewerActivity)
                .setTitle("图片信息").setMessage(text)
                .setPositiveButton("关闭", null).show()
        }
    }

    private fun buildExifText(localPath: String?, url: String, name: String, size: String): String {
        val sb = StringBuilder()
        sb.appendLine("文件名：$name")
        if (size.isNotEmpty()) sb.appendLine("大小：${formatSize(size.toLongOrNull() ?: 0L)}")
        val filePath = try { resolveFilePath(localPath, url, cacheDir) } catch (_: Exception) { null }
        if (filePath != null && File(filePath).exists()) {
            try {
                val exif = ExifInterface(filePath)
                listOf(
                    "分辨率" to run {
                        val w = exif.getAttribute(ExifInterface.TAG_IMAGE_WIDTH)
                        val h = exif.getAttribute(ExifInterface.TAG_IMAGE_LENGTH)
                        if (w != null && h != null) "${w} × ${h}" else null
                    },
                    "拍摄时间" to (exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) ?: exif.getAttribute(ExifInterface.TAG_DATETIME)),
                    "相机品牌" to exif.getAttribute(ExifInterface.TAG_MAKE),
                    "相机型号" to exif.getAttribute(ExifInterface.TAG_MODEL),
                    "光圈" to exif.getAttribute(ExifInterface.TAG_F_NUMBER)?.let { "f/$it" },
                    "快门速度" to exif.getAttribute(ExifInterface.TAG_EXPOSURE_TIME)?.let { "${it}s" },
                    "ISO" to exif.getAttribute(ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY),
                    "焦距" to exif.getAttribute(ExifInterface.TAG_FOCAL_LENGTH)?.let { "${it}mm" },
                    "软件" to exif.getAttribute(ExifInterface.TAG_SOFTWARE),
                    "GPS" to run {
                        val lat = exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE)
                        val lon = exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE)
                        if (lat != null && lon != null) "$lat, $lon" else null
                    }
                ).forEach { (label, value) -> if (!value.isNullOrEmpty()) sb.appendLine("$label：$value") }
            } catch (_: Exception) {}
        }
        return sb.toString().trimEnd()
    }

    private fun formatSize(bytes: Long) = when {
        bytes <= 0 -> "未知"
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> "%.1f KB".format(bytes / 1024.0)
        bytes < 1024 * 1024 * 1024 -> "%.1f MB".format(bytes / (1024.0 * 1024))
        else -> "%.2f GB".format(bytes / (1024.0 * 1024 * 1024))
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    override fun onDestroy() {
        super.onDestroy()
        slideshowHandler.removeCallbacks(slideshowRunnable)
        scope.cancel()
    }
}

// ─── Adapter（支持旋转）──────────────────────────────────────────────────────

class HeicPagerAdapter(
    private val urls: List<String>,
    private val localPaths: List<String>,
    private val screenLongEdge: Int,
    private val scope: CoroutineScope,
) : RecyclerView.Adapter<HeicPagerAdapter.VH>() {

    private val bitmapCache = mutableMapOf<Int, Bitmap>()
    private val loadingJobs = mutableMapOf<Int, Job>()
    // 每页的旋转角度（0/90/180/270）
    private val rotations = mutableMapOf<Int, Int>()

    inner class VH(view: View) : RecyclerView.ViewHolder(view) {
        val photoView: PhotoView = view.findViewById(R.id.photo_view)
        val progress: ProgressBar = view.findViewById(R.id.item_progress)
        val tvError: TextView = view.findViewById(R.id.tv_error)
        var currentIndex: Int = -1
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_heic_page, parent, false)
        return VH(view)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.currentIndex = position
        holder.tvError.visibility = View.GONE

        val cached = bitmapCache[position]
        if (cached != null && !cached.isRecycled) {
            showBitmap(holder, cached, rotations[position] ?: 0)
            return
        }

        holder.photoView.visibility = View.INVISIBLE
        holder.progress.visibility = View.VISIBLE
        loadingJobs[position]?.cancel()

        val localPath = localPaths.getOrNull(position)?.takeIf { it.isNotEmpty() }
        val url = urls.getOrNull(position) ?: return
        val cacheDir = holder.itemView.context.cacheDir

        loadingJobs[position] = scope.launch {
            val bitmap = withContext(Dispatchers.IO) { decodeHeic(localPath, url, screenLongEdge, cacheDir) }
            if (holder.currentIndex == position) {
                if (bitmap != null) {
                    bitmapCache[position] = bitmap
                    showBitmap(holder, bitmap, rotations[position] ?: 0)
                } else {
                    holder.progress.visibility = View.GONE
                    holder.tvError.text = "加载失败"
                    holder.tvError.visibility = View.VISIBLE
                }
            }
        }
    }

    private fun showBitmap(holder: VH, bitmap: Bitmap, rotation: Int) {
        holder.progress.visibility = View.GONE
        holder.photoView.setImageBitmap(bitmap)
        holder.photoView.rotation = rotation.toFloat()
        holder.photoView.visibility = View.VISIBLE
    }

    /** 旋转指定页 90 度 */
    fun rotatePage(index: Int) {
        val current = rotations[index] ?: 0
        rotations[index] = (current + 90) % 360
        notifyItemChanged(index)
    }

    override fun getItemCount() = urls.size

    override fun onViewRecycled(holder: VH) {
        super.onViewRecycled(holder)
        loadingJobs[holder.currentIndex]?.cancel()
        holder.photoView.setImageBitmap(null)
    }
}

// ─── 解码 & 网络 ─────────────────────────────────────────────────────────────

val httpClient by lazy { OkHttpClient() }

fun decodeHeic(localPath: String?, url: String, screenLongEdge: Int, cacheDir: File): Bitmap? {
    return try {
        val filePath = resolveFilePath(localPath, url, cacheDir) ?: return null
        val file = File(filePath)
        if (!file.exists()) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val source = ImageDecoder.createSource(file)
            val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                val srcW = info.size.width; val srcH = info.size.height
                val longEdge = maxOf(srcW, srcH)
                if (longEdge > screenLongEdge && srcW > 0 && srcH > 0) {
                    val scale = longEdge.toFloat() / screenLongEdge
                    decoder.setTargetSize((srcW / scale).toInt().coerceAtLeast(1), (srcH / scale).toInt().coerceAtLeast(1))
                }
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
            if (bitmap.config != Bitmap.Config.ARGB_8888) { val c = bitmap.copy(Bitmap.Config.ARGB_8888, false); bitmap.recycle(); c } else bitmap
        } else {
            val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeFile(filePath, opts)
            var s = 1; while (maxOf(opts.outWidth, opts.outHeight) / (s * 2) > screenLongEdge) s *= 2
            android.graphics.BitmapFactory.decodeFile(filePath, android.graphics.BitmapFactory.Options().apply { inSampleSize = s; inPreferredConfig = Bitmap.Config.ARGB_8888 })
        }
    } catch (e: Exception) { android.util.Log.e("HeicViewer", "decode failed: $e"); null }
}

fun resolveFilePath(localPath: String?, url: String, cacheDir: File): String? {
    if (!localPath.isNullOrEmpty() && File(localPath).exists()) return localPath
    if (url.isEmpty()) return null
    val cacheFile = File(cacheDir, "heic_${url.hashCode()}.heic")
    if (cacheFile.exists()) return cacheFile.absolutePath
    return try {
        val response = httpClient.newCall(Request.Builder().url(url).build()).execute()
        if (!response.isSuccessful) return null
        val body = response.body ?: return null
        cacheDir.mkdirs()
        FileOutputStream(cacheFile).use { it.write(body.bytes()) }
        response.close()
        cacheFile.absolutePath
    } catch (e: Exception) { android.util.Log.e("HeicViewer", "download failed: $e"); null }
}
