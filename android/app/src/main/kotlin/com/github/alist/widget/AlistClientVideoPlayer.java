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
    private View llPlayingAtDoubleSpeed;
    protected boolean isEnableSeek;
    private boolean isLongPressing;
    private ValueAnimator ffwdIconAnimator;

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

    private OnDeleteClickListener deleteClickListener;
    private OnPlaylistClickListener playlistClickListener;
    private OnInfoClickListener infoClickListener;
    private OnFavoriteClickListener favoriteClickListener;

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
        btnPrevious = findViewById(R.id.btn_previous);
        btnNext = findViewById(R.id.btn_next);
        btnRewind = findViewById(R.id.btn_rewind);
        btnFfwd = findViewById(R.id.btn_ffwd);
        btnScreenshot = findViewById(R.id.btn_screenshot);
        btnDelete = findViewById(R.id.btn_delete);
        btnPlaylist = findViewById(R.id.btn_playlist);
        btnInfo = findViewById(R.id.btn_info);
        btnFavorite = findViewById(R.id.btn_favorite);
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
        btnPrevious.setVisibility(visibility);
        btnNext.setVisibility(visibility);
        if (isEnableSeek) {
            btnRewind.setVisibility(visibility);
            btnFfwd.setVisibility(visibility);
        }
    }

    @Override
    protected void hideAllWidget() {
        super.hideAllWidget();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToNormal() {
        super.changeUiToNormal();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    protected void changeUiToPreparingShow() {
        super.changeUiToPreparingShow();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToPlayingShow() {
        super.changeUiToPlayingShow();
        if (!this.mLockCurScreen || !this.mNeedLockFull) {
            setCenterButtonsVisibility(View.VISIBLE);
        }
    }

    @Override
    protected void changeUiToPauseShow() {
        super.changeUiToPauseShow();
        if (!this.mLockCurScreen || !this.mNeedLockFull) {
            setCenterButtonsVisibility(View.VISIBLE);
        }
    }

    @Override
    protected void changeUiToPlayingBufferingShow() {
        super.changeUiToPlayingBufferingShow();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToCompleteShow() {
        super.changeUiToCompleteShow();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    protected void changeUiToError() {
        super.changeUiToError();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    protected void changeUiToPrepareingClear() {
        super.changeUiToPrepareingClear();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToPlayingBufferingClear() {
        super.changeUiToPlayingBufferingClear();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToClear() {
        super.changeUiToClear();
        setCenterButtonsVisibility(View.INVISIBLE);
    }

    @Override
    protected void changeUiToCompleteClear() {
        super.changeUiToCompleteClear();
        setCenterButtonsVisibility(View.VISIBLE);
    }

    @Override
    public GSYBaseVideoPlayer startWindowFullscreen(Context context, boolean actionBar, boolean statusBar) {
        AlistClientVideoPlayer videoPlayer = (AlistClientVideoPlayer) super.startWindowFullscreen(context, actionBar, statusBar);
        if (videoPlayer != null) {
            videoPlayer.isEnableSeek = this.isEnableSeek;

            if (isEnableSeek && videoPlayer.getStartButton() != null && videoPlayer.getStartButton().getVisibility() == View.VISIBLE) {
                videoPlayer.setCenterButtonsVisibility(View.VISIBLE);
            }
            videoPlayer.btnScreenshot.setOnClickListener(v -> videoPlayer.takeScreenshot());
            // propagate listeners to fullscreen instance
            videoPlayer.deleteClickListener = this.deleteClickListener;
            videoPlayer.playlistClickListener = this.playlistClickListener;
            videoPlayer.infoClickListener = this.infoClickListener;
            videoPlayer.favoriteClickListener = this.favoriteClickListener;
            
            // Re-attach click listeners to the fullscreen buttons
            if (videoPlayer.btnDelete != null && this.deleteClickListener != null) {
                videoPlayer.btnDelete.setOnClickListener(v -> {
                    if (videoPlayer.deleteClickListener != null) {
                        videoPlayer.deleteClickListener.onDeleteClick();
                    }
                });
            }
            if (videoPlayer.btnPlaylist != null && this.playlistClickListener != null) {
                videoPlayer.btnPlaylist.setOnClickListener(v -> {
                    // Exit fullscreen first, then trigger playlist
                    if (videoPlayer.playlistClickListener != null) {
                        videoPlayer.backFromFull(context);
                        // Delay to ensure fullscreen exit completes
                        videoPlayer.postDelayed(() -> {
                            if (this.playlistClickListener != null) {
                                this.playlistClickListener.onPlaylistClick();
                            }
                        }, 300);
                    }
                });
            }
            if (videoPlayer.btnInfo != null && this.infoClickListener != null) {
                videoPlayer.btnInfo.setOnClickListener(v -> {
                    if (videoPlayer.infoClickListener != null) {
                        videoPlayer.infoClickListener.onInfoClick();
                    }
                });
            }
            if (videoPlayer.btnFavorite != null && this.favoriteClickListener != null) {
                videoPlayer.btnFavorite.setOnClickListener(v -> {
                    if (videoPlayer.favoriteClickListener != null) {
                        videoPlayer.favoriteClickListener.onFavoriteClick();
                    }
                });
            }
        }
        return videoPlayer;
    }

    public View getBtnScreenshot() {
        return btnScreenshot;
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
