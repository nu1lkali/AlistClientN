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
        // 限制最大边为 1024，减少内存占用，防止闪退
        screenLongEdge = minOf(maxOf(dm.widthPixels, dm.heightPixels), 1024)

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
        // 限制预加载数量，减少内存占用
        viewPager.offscreenPageLimit = 1
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

        // 显示 Loading 对话框，避免用户无感等待
        val loadingDialog = AlertDialog.Builder(this)
            .setMessage("正在保存...")
            .setCancelable(false)
            .create()
        loadingDialog.show()

        scope.launch {
            val success = withContext(Dispatchers.IO) {
                try {
                    val sourceFile = if (localPath != null && File(localPath).exists()) {
                        File(localPath)
                    } else {
                        val ext = name.substringAfterLast('.', "heic").lowercase()
                        val cacheFile = File(cacheDir, "img_${url.hashCode()}.$ext")
                        if (!cacheFile.exists()) {
                            val resp = httpClient.newCall(Request.Builder().url(url).build()).execute()
                            if (!resp.isSuccessful) { resp.close(); return@withContext false }
                            // 流式写入，避免大文件一次性读入内存
                            resp.body?.byteStream()?.use { input ->
                                FileOutputStream(cacheFile).use { output -> input.copyTo(output) }
                            } ?: run { resp.close(); return@withContext false }
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
            loadingDialog.dismiss()
            toast(if (success) "已保存到相册" else "保存失败")
        }
    }

    private fun saveFileToGallery(file: File, name: String): Boolean {
        val mimeType = when (name.substringAfterLast('.', "").lowercase()) {
            "heic", "heif" -> "image/heic"
            "jpg", "jpeg"  -> "image/jpeg"
            "png"          -> "image/png"
            "webp"         -> "image/webp"
            "gif"          -> "image/gif"
            else           -> "image/*"
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
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

        val filePath = try { resolveFilePath(localPath, url, cacheDir) } catch (_: Exception) { null }
        val file = filePath?.let { File(it) }?.takeIf { it.exists() }

        // 文件大小：优先从磁盘读，其次用传入的 size
        val diskSize = file?.length() ?: 0L
        val displaySize = if (diskSize > 0) diskSize else size.toLongOrNull() ?: 0L
        if (displaySize > 0) sb.appendLine("大小：${formatSize(displaySize)}")

        // 文件修改时间
        if (file != null) {
            val lastModified = file.lastModified()
            if (lastModified > 0) {
                val sdf = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
                sb.appendLine("修改时间：${sdf.format(java.util.Date(lastModified))}")
            }
        }

        // 实际分辨率（用 ImageDecoder 解码 header，比 EXIF 更准确）
        if (file != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val source = ImageDecoder.createSource(file)
                // onHeaderDecoded 只读 header，不完整解码，速度快
                var actualW = 0; var actualH = 0
                ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    actualW = info.size.width; actualH = info.size.height
                    decoder.setTargetSize(1, 1) // 最小尺寸，只为拿到 info
                }.recycle()
                if (actualW > 0 && actualH > 0) sb.appendLine("分辨率：${actualW} × ${actualH}")
            } catch (_: Exception) {}
        }

        if (file != null) {
            try {
                val exif = ExifInterface(file.absolutePath)
                listOf(
                    "拍摄时间" to (exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                        ?: exif.getAttribute(ExifInterface.TAG_DATETIME)),
                    "相机品牌" to exif.getAttribute(ExifInterface.TAG_MAKE),
                    "相机型号" to exif.getAttribute(ExifInterface.TAG_MODEL),
                    "镜头型号" to exif.getAttribute(ExifInterface.TAG_LENS_MODEL),
                    "光圈" to exif.getAttribute(ExifInterface.TAG_F_NUMBER)?.let { "f/$it" },
                    "快门速度" to exif.getAttribute(ExifInterface.TAG_EXPOSURE_TIME)?.let {
                        // 转成更易读的分数形式，如 1/125s
                        val v = it.toDoubleOrNull()
                        if (v != null && v > 0 && v < 1.0) "1/${(1.0 / v).toInt()}s" else "${it}s"
                    },
                    "ISO" to exif.getAttribute(ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY)?.let { "ISO $it" },
                    "焦距" to exif.getAttribute(ExifInterface.TAG_FOCAL_LENGTH)?.let {
                        // EXIF 焦距格式是 "xx/yy"，转成小数
                        val parts = it.split("/")
                        if (parts.size == 2) {
                            val mm = parts[0].toDoubleOrNull()?.div(parts[1].toDoubleOrNull() ?: 1.0)
                            if (mm != null) "%.1fmm".format(mm) else "${it}mm"
                        } else "${it}mm"
                    },
                    "曝光补偿" to exif.getAttribute(ExifInterface.TAG_EXPOSURE_BIAS_VALUE)?.let {
                        val parts = it.split("/")
                        if (parts.size == 2) {
                            val ev = parts[0].toDoubleOrNull()?.div(parts[1].toDoubleOrNull() ?: 1.0)
                            if (ev != null) "%.1f EV".format(ev) else it
                        } else it
                    },
                    "白平衡" to exif.getAttribute(ExifInterface.TAG_WHITE_BALANCE)?.let {
                        if (it == "0") "自动" else if (it == "1") "手动" else it
                    },
                    "闪光灯" to exif.getAttribute(ExifInterface.TAG_FLASH)?.let {
                        val v = it.toIntOrNull() ?: 0
                        if (v and 0x1 == 0) "未触发" else "已触发"
                    },
                    "软件" to exif.getAttribute(ExifInterface.TAG_SOFTWARE),
                    "GPS" to run {
                        val latRef = exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE_REF)
                        val lonRef = exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF)
                        val lat = exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE)
                        val lon = exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE)
                        if (lat != null && lon != null) {
                            "${latRef ?: ""}$lat, ${lonRef ?: ""}$lon"
                        } else null
                    }
                ).forEach { (label, value) ->
                    if (!value.isNullOrEmpty()) sb.appendLine("$label：$value")
                }
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

    override fun onPause() {
        super.onPause()
        // 后台时停止幻灯片，避免资源浪费
        if (slideshowActive) {
            slideshowHandler.removeCallbacks(slideshowRunnable)
        }
    }

    override fun onResume() {
        super.onResume()
        // 回到前台时恢复幻灯片
        if (slideshowActive) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val seconds = prefs.getLong("flutter.slideshowIntervalSeconds", 3L).toInt().coerceIn(1, 60)
            slideshowHandler.postDelayed(slideshowRunnable, seconds * 1000L)
        }
    }

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

    // 关键修复：完全不缓存 bitmap，每次只加载当前页
    private val loadingJobs = mutableMapOf<Int, Job>()
    // 每页的旋转角度（0/90/180/270）
    private val rotations = mutableMapOf<Int, Int>()
    private val holderRefs = mutableMapOf<Int, java.lang.ref.WeakReference<VH>>()

    inner class VH(view: View) : RecyclerView.ViewHolder(view) {
        val photoView: PhotoView = view.findViewById(R.id.photo_view)
        val progress: ProgressBar = view.findViewById(R.id.item_progress)
        val tvError: TextView = view.findViewById(R.id.tv_error)
        var currentIndex: Int = -1
        // 存储当前正在显示的 bitmap，以便在回收时释放
        var displayedBitmap: Bitmap? = null
            set(value) {
                // 如果有旧的 bitmap 且与新的是不同对象，则回收
                if (field != null && field !== value && !field!!.isRecycled) {
                    field!!.recycle()
                }
                field = value
            }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_heic_page, parent, false)
        return VH(view)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.currentIndex = position
        holder.tvError.visibility = View.GONE
        holderRefs[position] = java.lang.ref.WeakReference(holder)

        holder.photoView.visibility = View.INVISIBLE
        holder.progress.visibility = View.VISIBLE
        
        // 取消之前的加载任务，防止加载旧的图片
        loadingJobs[position]?.cancel()
        loadingJobs.remove(position)

        val localPath = localPaths.getOrNull(position)?.takeIf { it.isNotEmpty() }
        val url = urls.getOrNull(position) ?: return
        val cacheDir = holder.itemView.context.cacheDir

        loadingJobs[position] = scope.launch {
            val bitmap = withContext(Dispatchers.IO) { decodeHeic(localPath, url, screenLongEdge, cacheDir) }
            // 只有当 holder 还绑定到同一个位置时才显示
            if (holder.currentIndex == position && holderRefs[position]?.get() === holder) {
                if (bitmap != null) {
                    holder.displayedBitmap = bitmap
                    showBitmap(holder, bitmap, rotations[position] ?: 0)
                } else {
                    holder.progress.visibility = View.GONE
                    holder.tvError.text = "加载失败"
                    holder.tvError.visibility = View.VISIBLE
                }
            } else {
                // 位置已改变，回收这个 bitmap
                bitmap?.recycle()
            }
            loadingJobs.remove(position)
        }
    }

    private fun showBitmap(holder: VH, bitmap: Bitmap, rotation: Int) {
        holder.progress.visibility = View.GONE
        holder.photoView.setImageBitmap(bitmap)
        holder.photoView.rotation = rotation.toFloat()
        holder.photoView.visibility = View.VISIBLE
    }

    /** 问题4修复：旋转时直接操作当前 PhotoView，不触发 onBindViewHolder */
    fun rotatePage(index: Int) {
        val newRotation = ((rotations[index] ?: 0) + 90) % 360
        rotations[index] = newRotation
        holderRefs[index]?.get()?.let { holder ->
            if (holder.currentIndex == index) {
                holder.photoView.rotation = newRotation.toFloat()
            }
        }
    }

    override fun getItemCount() = urls.size

    override fun onViewRecycled(holder: VH) {
        super.onViewRecycled(holder)
        loadingJobs[holder.currentIndex]?.cancel()
        loadingJobs.remove(holder.currentIndex)
        holderRefs.remove(holder.currentIndex)
        // 关键修复：回收当前显示的 bitmap
        holder.displayedBitmap?.let { bitmap ->
            if (!bitmap.isRecycled) bitmap.recycle()
        }
        holder.displayedBitmap = null
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
            // 问题3修复：保留 HARDWARE 配置，不强制 copy 到 ARGB_8888，避免双倍内存
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                val srcW = info.size.width; val srcH = info.size.height
                val longEdge = maxOf(srcW, srcH)
                if (longEdge > screenLongEdge && srcW > 0 && srcH > 0) {
                    val scale = longEdge.toFloat() / screenLongEdge
                    decoder.setTargetSize(
                        (srcW / scale).toInt().coerceAtLeast(1),
                        (srcH / scale).toInt().coerceAtLeast(1)
                    )
                }
                // 不强制 ALLOCATOR_SOFTWARE，让系统选择最优分配器
            }
        } else {
            val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeFile(filePath, opts)
            var s = 1; while (maxOf(opts.outWidth, opts.outHeight) / (s * 2) > screenLongEdge) s *= 2
            android.graphics.BitmapFactory.decodeFile(filePath, android.graphics.BitmapFactory.Options().apply {
                inSampleSize = s
                inPreferredConfig = Bitmap.Config.ARGB_8888
            })
        }
    } catch (e: Exception) { android.util.Log.e("HeicViewer", "decode failed: $e"); null }
}

fun resolveFilePath(localPath: String?, url: String, cacheDir: File): String? {
    if (!localPath.isNullOrEmpty() && File(localPath).exists()) return localPath
    if (url.isEmpty()) return null
    val ext = url.substringAfterLast('.', "heic").substringBefore('?').lowercase()
        .let { if (it.length > 5) "heic" else it }
    val cacheFile = File(cacheDir, "img_${url.hashCode()}.$ext")
    if (cacheFile.exists()) return cacheFile.absolutePath
    return try {
        val response = httpClient.newCall(Request.Builder().url(url).build()).execute()
        if (!response.isSuccessful) { response.close(); return null }
        val body = response.body ?: run { response.close(); return null }
        cacheDir.mkdirs()
        // 问题6修复：流式写入，避免大文件一次性 bytes() 读入内存
        body.byteStream().use { input ->
            FileOutputStream(cacheFile).use { output -> input.copyTo(output) }
        }
        response.close()
        cacheFile.absolutePath
    } catch (e: Exception) { android.util.Log.e("HeicViewer", "download failed: $e"); null }
}
