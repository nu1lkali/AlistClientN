package com.github.alist.utils;

import android.app.PictureInPictureParams;
import android.app.RemoteAction;
import android.util.Rational;

import java.util.List;

/**
 * PiP辅助类，用于创建PictureInPictureParams
 * 注意：setAutoExpandEnabled和setSeamlessResizeEnabled是@SystemApi，普通应用无法调用
 * 这里使用反射来调用这些隐藏API
 */
public class PipHelper {

    /**
     * 创建禁用自动展开和缩放的PictureInPictureParams
     * 通过反射调用隐藏的setAutoExpandEnabled和setSeamlessResizeEnabled方法
     */
    public static PictureInPictureParams createPipParams(Rational aspectRatio) {
        return createPipParams(aspectRatio, null);
    }

    /**
     * 创建禁用自动展开和缩放的PictureInPictureParams，并设置actions
     */
    public static PictureInPictureParams createPipParams(Rational aspectRatio, List<RemoteAction> actions) {
        PictureInPictureParams.Builder builder = new PictureInPictureParams.Builder();
        builder.setAspectRatio(aspectRatio);
        
        if (actions != null) {
            builder.setActions(actions);
        }
        
        // 使用反射调用隐藏API
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            try {
                java.lang.reflect.Method setAutoExpand = 
                    PictureInPictureParams.Builder.class.getMethod("setAutoExpandEnabled", boolean.class);
                setAutoExpand.invoke(builder, false);
            } catch (Exception e) {
                // 隐藏API不可用，忽略
            }
            try {
                java.lang.reflect.Method setSeamlessResize = 
                    PictureInPictureParams.Builder.class.getMethod("setSeamlessResizeEnabled", boolean.class);
                setSeamlessResize.invoke(builder, false);
            } catch (Exception e) {
                // 隐藏API不可用，忽略
            }
        }
        
        return builder.build();
    }
}
