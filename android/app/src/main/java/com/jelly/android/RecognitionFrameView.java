package com.jelly.android;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;

final class RecognitionFrameView extends View {
    private final Paint dimPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint cornerPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF frame = new RectF();
    private final ScaleGestureDetector scaleDetector;

    private float lastX;
    private float lastY;
    private boolean dragging;

    RecognitionFrameView(Context context) {
        super(context);
        dimPaint.setColor(Color.argb(82, 0, 0, 0));
        borderPaint.setStyle(Paint.Style.STROKE);
        borderPaint.setStrokeWidth(dp(2));
        borderPaint.setColor(Color.WHITE);
        cornerPaint.setStyle(Paint.Style.STROKE);
        cornerPaint.setStrokeWidth(dp(5));
        cornerPaint.setStrokeCap(Paint.Cap.ROUND);
        cornerPaint.setColor(Color.rgb(242, 163, 58));
        scaleDetector = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override
            public boolean onScale(ScaleGestureDetector detector) {
                resize(detector.getScaleFactor());
                return true;
            }
        });
    }

    RectF getFrameRect() {
        return new RectF(frame);
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        if (frame.isEmpty()) {
            float frameWidth = width * 0.76f;
            float frameHeight = height * 0.34f;
            frame.set(
                    (width - frameWidth) / 2f,
                    height * 0.18f,
                    (width + frameWidth) / 2f,
                    height * 0.18f + frameHeight
            );
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        canvas.drawRect(0, 0, getWidth(), frame.top, dimPaint);
        canvas.drawRect(0, frame.bottom, getWidth(), getHeight(), dimPaint);
        canvas.drawRect(0, frame.top, frame.left, frame.bottom, dimPaint);
        canvas.drawRect(frame.right, frame.top, getWidth(), frame.bottom, dimPaint);
        canvas.drawRoundRect(frame, dp(14), dp(14), borderPaint);

        float l = dp(28);
        canvas.drawLine(frame.left, frame.top + l, frame.left, frame.top, cornerPaint);
        canvas.drawLine(frame.left, frame.top, frame.left + l, frame.top, cornerPaint);
        canvas.drawLine(frame.right - l, frame.top, frame.right, frame.top, cornerPaint);
        canvas.drawLine(frame.right, frame.top, frame.right, frame.top + l, cornerPaint);
        canvas.drawLine(frame.left, frame.bottom - l, frame.left, frame.bottom, cornerPaint);
        canvas.drawLine(frame.left, frame.bottom, frame.left + l, frame.bottom, cornerPaint);
        canvas.drawLine(frame.right - l, frame.bottom, frame.right, frame.bottom, cornerPaint);
        canvas.drawLine(frame.right, frame.bottom - l, frame.right, frame.bottom, cornerPaint);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        scaleDetector.onTouchEvent(event);

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                lastX = event.getX();
                lastY = event.getY();
                dragging = frame.contains(lastX, lastY);
                return true;
            case MotionEvent.ACTION_MOVE:
                if (dragging && event.getPointerCount() == 1) {
                    float dx = event.getX() - lastX;
                    float dy = event.getY() - lastY;
                    frame.offset(dx, dy);
                    clampFrame();
                    lastX = event.getX();
                    lastY = event.getY();
                    invalidate();
                }
                return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                dragging = false;
                return true;
            default:
                return true;
        }
    }

    private void resize(float scale) {
        float centerX = frame.centerX();
        float centerY = frame.centerY();
        float newWidth = Math.max(dp(140), Math.min(getWidth() - dp(32), frame.width() * scale));
        float newHeight = Math.max(dp(90), Math.min(getHeight() - dp(240), frame.height() * scale));
        frame.set(centerX - newWidth / 2f, centerY - newHeight / 2f, centerX + newWidth / 2f, centerY + newHeight / 2f);
        clampFrame();
        invalidate();
    }

    private void clampFrame() {
        float padding = dp(16);
        if (frame.left < padding) {
            frame.offset(padding - frame.left, 0);
        }
        if (frame.right > getWidth() - padding) {
            frame.offset(getWidth() - padding - frame.right, 0);
        }
        if (frame.top < padding + dp(48)) {
            frame.offset(0, padding + dp(48) - frame.top);
        }
        if (frame.bottom > getHeight() - padding - dp(150)) {
            frame.offset(0, getHeight() - padding - dp(150) - frame.bottom);
        }
    }

    private float dp(float value) {
        return value * getResources().getDisplayMetrics().density;
    }
}
