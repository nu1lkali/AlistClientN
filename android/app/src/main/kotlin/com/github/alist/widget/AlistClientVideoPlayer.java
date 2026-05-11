package com.github.alist.widget;

import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.content.ContentValues;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Outline;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.AttributeSet;
import android.util.DisplayMetrics;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.SurfaceView;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.core.view.GestureDetectorCompat;

import com.github.alist.client.R;
import com.shuyu.gsyvideoplayer.video.NormalGSYVideoPlayer;
import com.shuyu.gsyvideoplayer.video.base.GSYBaseVideoPlayer;
import com.shuyu.gsyvideoplayer.video.base.GSYVideoView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class AlistClientVideoPlayer extends NormalGSYVideoPlayer {
    private GestureDetectorCompat gestureDetector;
    protected View btnPrevious;
    protected View btnNext;
    protected View btnRewind;
    protected View btnFfwd;
    protected View btnScreenshot;
    protected View btnDelete;
    protected View btnPlaylist;
    protected View btnInfo;
    protected View btnFavorite;
    protected View btnPip;
    private View llPlayingAtDoubleSpeed;
    private View llQuickNav;
    private View btnQuickPrevious;
    private View btnQuickNext;
    protected boolean isEnableSeek;
    private boolean isLongPressing;
    private ValueAnimator ffwdIconAnimator;
    // 画中画模式标记，为true时阻止自定义UI显示
    private boolean isInPipMode = false;

    public interface OnDeleteClickListener {
        void onDeleteClick();
    }

    public interface OnPlaylistClickListener {
        void onPlaylistClick();
    }

    public interface OnInfoClickListener {
        void onInfoClick();
    }

    public interface OnFavoriteClickListener {
        void onFavoriteClick();
    }

    public interface OnPipClickListener {
        void onPipClick();
    }

    private OnDeleteClickListener deleteClickListener;
    private OnPlaylistClickListener playlistClickListener;
    private OnInfoClickListener infoClickListener;
    private OnFavoriteClickListener favoriteClickListener;
    private OnPipClickListener pipClickListener;

    public void setOnDeleteClickListener(OnDeleteClickListener listener) {
        this.deleteClickListener = listener;
        if (btnDelete != null) {
            btnDelete.setOnClickListener(v -> {
                if (deleteClickListener != null) deleteClickListener.onDeleteClick();
            });
        }
    }

    public void setOnPlaylistClickListener(OnPlaylistClickListener listener) {
        this.playlistClickListener = listener;
        if (btnPlaylist != null) {
            btnPlaylist.setOnClickListener(v -> {
                if (playlistClickListener != null) playlistClickListener.onPlaylistClick();
            });
        }
    }

    public void setOnInfoClickListener(OnInfoClickListener listener) {
        this.infoClickListener = listener;
        if (btnInfo != null) {
            btnInfo.setOnClickListener(v -> {
                if (infoClickListener != null) infoClickListener.onInfoClick();
            });
        }
    }

    public void setOnFavoriteClickListener(OnFavoriteClickListener listener) {
        this.favoriteClickListener = listener;
        if (btnFavorite != null) {
            btnFavorite.setOnClickListener(v -> {
                if (favoriteClickListener != null) favoriteClickListener.onFavoriteClick();
            });
        }
    }

    public void setOnPipClickListener(OnPipClickListener listener) {
        this.pipClickListener = listener;
        if (btnPip != null) {
            btnPip.setOnClickListener(v -> {
                if (pipClickListener != null) pipClickListener.onPipClick();
            });
        }
    }

    public AlistClientVideoPlayer(Context context, Boolean fullFlag) {
        super(context, fullFlag);
    }

    public AlistClientVideoPlayer(Context context) {
        super(context);
    }

    public AlistClientVideoPlayer(Context context, AttributeSet attrs) {
        super(context, attrs);
    }

    @Override
    protected void init(Context context) {
        super.init(context);
        VideoPlayerGestureListener gestureListener = new VideoPlayerGestureListener();
        gestureDetector = new GestureDetectorCompat(context, gestureListener);
        gestureDetector.setIsLongpressEnabled(true);
        llPlayingAtDoubleSpeed = findViewById(R.id.ll_playing_at_double_speed);
        llQuickNav = findViewById(R.id.ll_quick_nav);
        btnQuickPrevious = findViewById(R.id.btn_quick_previous);
        btnQuickNext = findViewById(R.id.btn_quick_next);
        btnPrevious = findViewById(R.id.btn_previous);
        btnNext = findViewById(R.id.btn_next);
        btnRewind = findViewById(R.id.btn_rewind);
        btnFfwd = findViewById(R.id.btn_ffwd);
        btnScreenshot = findViewById(R.id.btn_screenshot);
        btnDelete = findViewById(R.id.btn_delete);
        btnPlaylist = findViewById(R.id.btn_playlist);
        btnInfo = findViewById(R.id.btn_info);
        btnFavorite = findViewById(R.id.btn_favorite);
        btnPip = findViewById(R.id.btn_pip);
        btnRewind.setVisibility(View.INVISIBLE);
        btnFfwd.setVisibility(View.INVISIBLE);
        btnScreenshot.setOnClickListener(v -> takeScreenshot());

        View ivPlayingAtDoubleSpeed = findViewById(R.id.iv_playing_at_double_speed);
        ffwdIconAnimator = ObjectAnimator.ofFloat(ivPlayingAtDoubleSpeed, "alpha", 1f, 0f);
        ffwdIconAnimator.setRepeatMode(ValueAnimator.REVERSE);
        ffwdIconAnimator.setRepeatCount(ValueAnimator.INFINITE);
        btnRewind.setOnClickListener(v -> {
            if (getDuration() > 0L) {
                long targetPosition =
                        Math.max(0, getGSYVideoManager().getCurrentPosition() - 10000);
                getGSYVideoManager().seekTo(targetPosition);
            }
        });
        btnFfwd.setOnClickListener(v -> {
            long duration = getDuration();
            if (duration > 0L) {
                long targetPosition = Math.min(duration, getGSYVideoManager().getCurrentPosition() + 10000);
                getGSYVideoManager().seekTo(targetPosition);
            }
        });
        // 悬浮快捷按钮转发给中间按钮
        btnQuickPrevious.setOnClickListener(v -> btnPrevious.performClick());
        btnQuickNext.setOnClickListener(v -> btnNext.performClick());

        llPlayingAtDoubleSpeed.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
                int radius = dp2Px(2);
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
            }
        });
        llPlayingAtDoubleSpeed.setClipToOutline(true);
    }

    private int dp2Px(int dp) {
        DisplayMetrics displayMetrics = getContext().getResources().getDisplayMetrics();
        return Math.round(displayMetrics.density * dp);
    }

    public View getBtnPrevious() {
        return btnPrevious;
    }

    public View getBtnNext() {
        return btnNext;
    }

    public View getBtnRewind() {
        return btnRewind;
    }

    public View getBtnFfwd() {
        return btnFfwd;
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        if (llPlayingAtDoubleSpeed.getVisibility() == View.VISIBLE) {
            ffwdIconAnimator.start();
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        ffwdIconAnimator.cancel();
    }

    @Override
    public boolean onTouch(View v, MotionEvent event) {
        // 画中画模式下，拦截所有触摸事件，防止点击触发UI显示
        if (isInPipMode) {
            return true;
        }
        if (v.getId() == R.id.surface_container && this.mIfCurrentIsFullscreen && !this.mLockCurScreen) {
            if ((event.getActionMasked() == MotionEvent.ACTION_UP || event.getActionMasked() == MotionEvent.ACTION_CANCEL) && isLongPressing) {
                isLongPressing = false;
                llPlayingAtDoubleSpeed.setVisibility(View.INVISIBLE);
                ffwdIconAnimator.cancel();
                setSpeedPlaying(1, true);
            }
            gestureDetector.onTouchEvent(event);
        }
        return super.onTouch(v, event);
    }

    @Override
    public void onPrepared() {
        super.onPrepared();
        isEnableSeek = getDuration() > 0L;
        if (isEnableSeek) {
            btnRewind.setVisibility(View.VISIBLE);
            btnFfwd.setVisibility(View.VISIBLE);
        } else {
            btnRewind.setVisibility(View.GONE);
            btnFfwd.setVisibility(View.GONE);
        }
    }

    protected void setCenterButtonsVisibility(int visibility) {
        // 画中画模式下，始终隐藏自定义UI控件
        if (isInPipMode) {
            visibility = View.GONE;
        }
        btnPrevious.setVisibility(visibility);
        btnNext.setVisibility(visibility);
        if (isEnableSeek) {
            btnRewind.setVisibility(visibility);
            btnFfwd.setVisibility(visibility);
        }
        // 悬浮快捷按钮跟随控制栏
        llQuickNav.setVisibility(visibility);
    }

    @Override
    protected void hideAllWidget() {
        // 画中画模式下，跳过父类hideAllWidget，避免触发父类UI逻辑
        if (!isInPipMode) {
            super.hideAllWidget();
        }
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToNormal() {
        // 画中画模式下，跳过所有父类UI变更逻辑
        if (isInPipMode) return;
        super.changeUiToNormal();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    protected void changeUiToPreparingShow() {
        if (isInPipMode) return;
        super.changeUiToPreparingShow();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToPlayingShow() {
        if (isInPipMode) return;
        super.changeUiToPlayingShow();
        if (!this.mLockCurScreen || !this.mNeedLockFull) {
            setCenterButtonsVisibility(View.VISIBLE);
        }
    }

    @Override
    protected void changeUiToPauseShow() {
        // 画中画模式下，跳过所有父类UI变更逻辑
        if (isInPipMode) return;
        super.changeUiToPauseShow();
        if (!this.mLockCurScreen || !this.mNeedLockFull) {
            setCenterButtonsVisibility(View.VISIBLE);
        }
    }

    @Override
    protected void changeUiToPlayingBufferingShow() {
        if (isInPipMode) return;
        super.changeUiToPlayingBufferingShow();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToCompleteShow() {
        if (isInPipMode) return;
        super.changeUiToCompleteShow();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    protected void changeUiToError() {
        if (isInPipMode) return;
        super.changeUiToError();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    protected void changeUiToPrepareingClear() {
        if (isInPipMode) return;
        super.changeUiToPrepareingClear();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToPlayingBufferingClear() {
        if (isInPipMode) return;
        super.changeUiToPlayingBufferingClear();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToClear() {
        if (isInPipMode) return;
        super.changeUiToClear();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToCompleteClear() {
        if (isInPipMode) return;
        super.changeUiToCompleteClear();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    public GSYBaseVideoPlayer startWindowFullscreen(Context context, boolean actionBar, boolean statusBar) {
        AlistClientVideoPlayer fullPlayer = (AlistClientVideoPlayer) super.startWindowFullscreen(context, actionBar, statusBar);
        if (fullPlayer != null) {
            // 同步 seek 状态，确保全屏下 rewind/ffwd 按钮正常显示
            fullPlayer.isEnableSeek = this.isEnableSeek;
            if (this.isEnableSeek) {
                fullPlayer.btnRewind.setVisibility(View.VISIBLE);
                fullPlayer.btnFfwd.setVisibility(View.VISIBLE);
            }
            // 同步其他监听器
            fullPlayer.deleteClickListener = this.deleteClickListener;
            fullPlayer.playlistClickListener = this.playlistClickListener;
            fullPlayer.infoClickListener = this.infoClickListener;
            fullPlayer.favoriteClickListener = this.favoriteClickListener;
            fullPlayer.pipClickListener = this.pipClickListener;
            fullPlayer.btnScreenshot.setOnClickListener(v -> fullPlayer.takeScreenshot());
            if (fullPlayer.btnDelete != null && fullPlayer.deleteClickListener != null) {
                fullPlayer.btnDelete.setOnClickListener(v -> {
                    if (fullPlayer.deleteClickListener != null) fullPlayer.deleteClickListener.onDeleteClick();
                });
            }
            if (fullPlayer.btnPlaylist != null && fullPlayer.playlistClickListener != null) {
                fullPlayer.btnPlaylist.setOnClickListener(v -> {
                    if (fullPlayer.playlistClickListener != null) fullPlayer.playlistClickListener.onPlaylistClick();
                });
            }
            if (fullPlayer.btnInfo != null && fullPlayer.infoClickListener != null) {
                fullPlayer.btnInfo.setOnClickListener(v -> {
                    if (fullPlayer.infoClickListener != null) fullPlayer.infoClickListener.onInfoClick();
                });
            }
            if (fullPlayer.btnFavorite != null && fullPlayer.favoriteClickListener != null) {
                fullPlayer.btnFavorite.setOnClickListener(v -> {
                    if (fullPlayer.favoriteClickListener != null) fullPlayer.favoriteClickListener.onFavoriteClick();
                });
            }
        }
        return fullPlayer;
    }

    public View getBtnScreenshot() {
        return btnScreenshot;
    }

    /**
     * 进入画中画模式 - 彻底隐藏所有自定义UI并禁用手势
     */
    public void enterPipMode() {
        this.isInPipMode = true;
        
        // 1. 调用GSY内置方法隐藏所有标准控件
        hideAllWidget();
        
        // 2. 强制隐藏所有自定义UI控件（使用GONE彻底移除占位）
        View layoutTop = findViewById(R.id.layout_top);
        if (layoutTop != null) layoutTop.setVisibility(View.GONE);
        
        View layoutBottom = findViewById(R.id.layout_bottom);
        if (layoutBottom != null) layoutBottom.setVisibility(View.GONE);
        
        View bottomProgressbar = findViewById(R.id.bottom_progressbar);
        if (bottomProgressbar != null) bottomProgressbar.setVisibility(View.GONE);
        
        // 中间控制按钮组
        setCenterButtonsVisibility(View.GONE);
        
        // 悬浮快捷导航
        if (llQuickNav != null) llQuickNav.setVisibility(View.GONE);
        
        // 倍速播放提示
        if (llPlayingAtDoubleSpeed != null) llPlayingAtDoubleSpeed.setVisibility(View.GONE);
        
        // 加载进度条
        View loading = findViewById(R.id.loading);
        if (loading != null) loading.setVisibility(View.GONE);
        
        // 锁屏按钮
        View lockScreen = findViewById(R.id.lock_screen);
        if (lockScreen != null) lockScreen.setVisibility(View.GONE);
        
        // 小关闭按钮
        View smallClose = findViewById(R.id.small_close);
        if (smallClose != null) smallClose.setVisibility(View.GONE);
        
        // 缩略图
        View thumb = findViewById(R.id.thumb);
        if (thumb != null) thumb.setVisibility(View.GONE);
        
        // 中间的大播放/暂停按钮
        View startButton = findViewById(R.id.start);
        if (startButton != null) startButton.setVisibility(View.GONE);
        
        // 3. 禁用手势操作，防止点击触发UI显示
        setIsTouchWiget(false);
        
        // 4. 确保surface_container没有额外背景/内边距导致黑边
        View surfaceContainer = findViewById(R.id.surface_container);
        if (surfaceContainer != null) {
            surfaceContainer.setBackgroundColor(android.graphics.Color.TRANSPARENT);
        }
    }

    /**
     * 退出画中画模式 - 恢复所有自定义UI和手势
     */
    public void exitPipMode() {
        this.isInPipMode = false;
        
        // 1. 恢复surface_container背景色
        View surfaceContainer = findViewById(R.id.surface_container);
        if (surfaceContainer != null) {
            surfaceContainer.setBackgroundColor(android.graphics.Color.BLACK);
        }
        
        // 2. 恢复手势操作
        setIsTouchWiget(true);
        
        // 3. 恢复所有自定义UI控件
        View layoutTop = findViewById(R.id.layout_top);
        if (layoutTop != null) layoutTop.setVisibility(View.VISIBLE);
        
        View layoutBottom = findViewById(R.id.layout_bottom);
        if (layoutBottom != null) layoutBottom.setVisibility(View.VISIBLE);
        
        View bottomProgressbar = findViewById(R.id.bottom_progressbar);
        if (bottomProgressbar != null) bottomProgressbar.setVisibility(View.VISIBLE);
        
        // 4. 根据当前播放状态恢复对应的UI
        int state = getCurrentPlayer().getCurrentState();
        if (state == GSYVideoView.CURRENT_STATE_PLAYING
            || state == GSYVideoView.CURRENT_STATE_PLAYING_BUFFERING_START) {
            changeUiToPlayingShow();
        } else if (state == GSYVideoView.CURRENT_STATE_PAUSE) {
            changeUiToPauseShow();
        } else {
            changeUiToNormal();
        }
    }

    private void takeScreenshot() {
        try {
            // find the actual video rendering view inside surface_container
            ViewGroup container = findViewById(R.id.surface_container);
            if (container == null) {
                Toast.makeText(getContext(), "截图失败", Toast.LENGTH_SHORT).show();
                return;
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.os.Handler handler = new android.os.Handler(android.os.Looper.getMainLooper());

                // prefer TextureView: supports getBitmap() directly
                TextureView textureView = findTextureView(container);
                if (textureView != null) {
                    Bitmap bitmap = textureView.getBitmap();
                    if (bitmap != null) {
                        saveBitmapToAlbum(bitmap);
                        return;
                    }
                }

                // fallback: PixelCopy on SurfaceView
                SurfaceView surfaceView = findSurfaceView(container);
                if (surfaceView != null) {
                    Bitmap bitmap = Bitmap.createBitmap(surfaceView.getWidth(), surfaceView.getHeight(), Bitmap.Config.ARGB_8888);
                    android.view.PixelCopy.request(surfaceView, bitmap, copyResult -> {
                        if (copyResult == android.view.PixelCopy.SUCCESS) {
                            saveBitmapToAlbum(bitmap);
                        } else {
                            Toast.makeText(getContext(), "截图失败", Toast.LENGTH_SHORT).show();
                        }
                    }, handler);
                    return;
                }

                Toast.makeText(getContext(), "截图失败：未找到视频渲染层", Toast.LENGTH_SHORT).show();
            } else {
                // API < 26: TextureView only
                TextureView textureView = findTextureView(container);
                if (textureView != null) {
                    Bitmap bitmap = textureView.getBitmap();
                    if (bitmap != null) {
                        saveBitmapToAlbum(bitmap);
                        return;
                    }
                }
                Toast.makeText(getContext(), "截图失败", Toast.LENGTH_SHORT).show();
            }
        } catch (Exception e) {
            Toast.makeText(getContext(), "截图失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private TextureView findTextureView(ViewGroup root) {
        for (int i = 0; i < root.getChildCount(); i++) {
            View child = root.getChildAt(i);
            if (child instanceof TextureView) return (TextureView) child;
            if (child instanceof ViewGroup) {
                TextureView found = findTextureView((ViewGroup) child);
                if (found != null) return found;
            }
        }
        return null;
    }

    private SurfaceView findSurfaceView(ViewGroup root) {
        for (int i = 0; i < root.getChildCount(); i++) {
            View child = root.getChildAt(i);
            if (child instanceof SurfaceView) return (SurfaceView) child;
            if (child instanceof ViewGroup) {
                SurfaceView found = findSurfaceView((ViewGroup) child);
                if (found != null) return found;
            }
        }
        return null;
    }

    private void saveBitmapToAlbum(Bitmap bitmap) {
        try {
            String fileName = "screenshot_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(new Date()) + ".jpg";
            OutputStream out;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ContentValues values = new ContentValues();
                values.put(MediaStore.Images.Media.DISPLAY_NAME, fileName);
                values.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
                values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES);
                Uri uri = getContext().getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
                if (uri == null) return;
                out = getContext().getContentResolver().openOutputStream(uri);
            } else {
                File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
                File file = new File(dir, fileName);
                out = new FileOutputStream(file);
            }
            if (out != null) {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out);
                out.close();
                Toast.makeText(getContext(), "截图已保存到相册", Toast.LENGTH_SHORT).show();
            }
        } catch (Exception e) {
            Toast.makeText(getContext(), "截图失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    @Override
    public int getLayoutId() {
        return R.layout.video_layout_alist_client;
    }



    private class VideoPlayerGestureListener extends GestureDetector.SimpleOnGestureListener {

        @Override
        public boolean onDown(@NonNull MotionEvent e) {
            return true;
        }

        @Override
        public boolean onSingleTapUp(@NonNull MotionEvent e) {
            performClick();
            return true;
        }

        @Override
        public void onLongPress(@NonNull MotionEvent e) {
            isLongPressing = true;
            if (getDuration() > 0) {
                setSpeedPlaying(2, true);
                llPlayingAtDoubleSpeed.setVisibility(View.VISIBLE);
                ffwdIconAnimator.start();
            }
        }
    }
}
