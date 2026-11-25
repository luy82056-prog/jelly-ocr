package com.jelly.android;

import android.Manifest;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.RectF;
import android.net.Uri;
import android.os.Bundle;
import android.view.OrientationEventListener;
import android.text.Selection;
import android.text.Spannable;
import android.view.Surface;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.ComponentActivity;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.camera.core.AspectRatio;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExperimentalGetImage;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@ExperimentalGetImage
public final class MainActivity extends ComponentActivity {
    private enum Screen {
        SCAN,
        LIST,
        DETAIL
    }

    private enum ScanState {
        SCANNING,
        LOCKED
    }

    private FrameLayout root;
    private PreviewView previewView;
    private RecognitionFrameView frameView;
    private LinearLayout resultCard;
    private TextView resultTextView;
    private TextView hintTextView;
    private Button primaryButton;
    private LinearLayout bottomBar;
    private Button scanTab;
    private Button listTab;

    private QuoteStore quoteStore;
    private TextRecognizer recognizer;
    private ExecutorService cameraExecutor;
    private ProcessCameraProvider cameraProvider;
    private Preview cameraPreview;
    private ImageAnalysis imageAnalysis;
    private OrientationEventListener orientationEventListener;
    private int currentTargetRotation = Surface.ROTATION_0;

    private Screen currentScreen = Screen.SCAN;
    private ScanState scanState = ScanState.SCANNING;
    private String liveText = "";
    private String lockedText = "";
    private int savedInLockSession = 0;
    private long lastAnalysisAt = 0L;
    private boolean isAnalyzing = false;

    private final ActivityResultLauncher<String> permissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), granted -> {
                if (granted) {
                    startCamera();
                } else {
                    showPermissionMessage();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        quoteStore = new QuoteStore(this);
        recognizer = TextRecognition.getClient(new ChineseTextRecognizerOptions.Builder().build());
        cameraExecutor = Executors.newSingleThreadExecutor();
        setupOrientationListener();
        showScan();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (cameraExecutor != null) {
            cameraExecutor.shutdown();
        }
        if (recognizer != null) {
            recognizer.close();
        }
        if (orientationEventListener != null) {
            orientationEventListener.disable();
        }
    }

    private void setupOrientationListener() {
        currentTargetRotation = getWindowManager().getDefaultDisplay().getRotation();
        orientationEventListener = new OrientationEventListener(this) {
            @Override
            public void onOrientationChanged(int orientation) {
                int rotation = getWindowManager().getDefaultDisplay().getRotation();
                if (rotation != currentTargetRotation) {
                    currentTargetRotation = rotation;
                    if (cameraPreview != null) {
                        cameraPreview.setTargetRotation(rotation);
                    }
                    if (imageAnalysis != null) {
                        imageAnalysis.setTargetRotation(rotation);
                    }
                }
            }
        };

        if (orientationEventListener.canDetectOrientation()) {
            orientationEventListener.enable();
        }
    }

    private void showScan() {
        currentScreen = Screen.SCAN;
        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        setContentView(root);

        previewView = new PreviewView(this);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        previewView.setScaleType(PreviewView.ScaleType.FIT_CENTER);
        root.addView(previewView, matchParent());

        frameView = new RecognitionFrameView(this);
        root.addView(frameView, matchParent());

        hintTextView = pillText("拖动或双指缩放取景框", Color.WHITE, Color.argb(92, 0, 0, 0));
        FrameLayout.LayoutParams hintParams = new FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        hintParams.topMargin = dp(44);
        root.addView(hintTextView, hintParams);

        resultCard = new LinearLayout(this);
        resultCard.setOrientation(LinearLayout.VERTICAL);
        resultCard.setPadding(dp(16), dp(14), dp(16), dp(14));
        resultCard.setBackground(rounded(Color.argb(238, 250, 250, 252), dp(10)));
        resultCard.setVisibility(View.GONE);

        TextView title = new TextView(this);
        title.setText("识别文本");
        title.setTextColor(Color.rgb(105, 105, 112));
        title.setTextSize(13);
        title.setTypeface(null, 1);
        resultCard.addView(title, new LinearLayout.LayoutParams(match(), wrap()));

        ScrollView textScroll = new ScrollView(this);
        resultTextView = new TextView(this);
        resultTextView.setTextColor(Color.rgb(20, 20, 24));
        resultTextView.setTextSize(16);
        resultTextView.setLineSpacing(dp(2), 1.0f);
        resultTextView.setTextIsSelectable(false);
        textScroll.addView(resultTextView, new ScrollView.LayoutParams(match(), wrap()));
        LinearLayout.LayoutParams textScrollParams = new LinearLayout.LayoutParams(match(), 0, 1f);
        textScrollParams.topMargin = dp(8);
        resultCard.addView(textScroll, textScrollParams);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER);
        actions.setVisibility(View.GONE);

        Button copyButton = actionButton("复制");
        Button saveButton = actionButton("保存");
        copyButton.setOnClickListener(v -> copyLockedText());
        saveButton.setOnClickListener(v -> saveLockedText());
        actions.addView(copyButton, weightButton());
        actions.addView(saveButton, weightButton());
        resultCard.addView(actions, new LinearLayout.LayoutParams(match(), dp(46)));
        resultCard.setTag(actions);

        FrameLayout.LayoutParams cardParams = new FrameLayout.LayoutParams(match(), dp(250), Gravity.BOTTOM);
        cardParams.leftMargin = dp(16);
        cardParams.rightMargin = dp(16);
        cardParams.bottomMargin = dp(150);
        root.addView(resultCard, cardParams);

        primaryButton = actionButton("锁定文字");
        primaryButton.setTextSize(17);
        primaryButton.setOnClickListener(v -> {
            if (scanState == ScanState.SCANNING) {
                lockText();
            } else {
                resetScan();
            }
        });
        FrameLayout.LayoutParams primaryParams = new FrameLayout.LayoutParams(match(), dp(54), Gravity.BOTTOM);
        primaryParams.leftMargin = dp(16);
        primaryParams.rightMargin = dp(16);
        primaryParams.bottomMargin = dp(88);
        root.addView(primaryButton, primaryParams);

        buildBottomBar();
        ensureCameraPermission();
    }

    private void buildBottomBar() {
        bottomBar = new LinearLayout(this);
        bottomBar.setGravity(Gravity.CENTER);
        bottomBar.setOrientation(LinearLayout.HORIZONTAL);
        bottomBar.setPadding(dp(8), dp(8), dp(8), dp(8));
        bottomBar.setBackgroundColor(Color.argb(232, 247, 247, 250));

        scanTab = tabButton("扫描", currentScreen == Screen.SCAN);
        listTab = tabButton("暂存", currentScreen == Screen.LIST);
        scanTab.setOnClickListener(v -> showScan());
        listTab.setOnClickListener(v -> showList());
        bottomBar.addView(scanTab, weightButton());
        bottomBar.addView(listTab, weightButton());

        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(match(), dp(74), Gravity.BOTTOM);
        root.addView(bottomBar, params);
    }

    private void ensureCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            permissionLauncher.launch(Manifest.permission.CAMERA);
        }
    }

    private void startCamera() {
        ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(this);
        cameraProviderFuture.addListener(() -> {
            try {
                cameraProvider = cameraProviderFuture.get();
                bindCamera();
            } catch (Exception error) {
                Toast.makeText(this, "相机启动失败", Toast.LENGTH_SHORT).show();
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void bindCamera() {
        if (cameraProvider == null || previewView == null) {
            return;
        }

        int targetRotation = getWindowManager().getDefaultDisplay().getRotation();
        currentTargetRotation = targetRotation;

        cameraPreview = new Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setTargetRotation(targetRotation)
                .build();
        cameraPreview.setSurfaceProvider(previewView.getSurfaceProvider());

        imageAnalysis = new ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setTargetRotation(targetRotation)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build();
        imageAnalysis.setAnalyzer(cameraExecutor, this::analyzeImage);

        cameraProvider.unbindAll();
        cameraProvider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, cameraPreview, imageAnalysis);
    }

    private void analyzeImage(@NonNull ImageProxy imageProxy) {
        long now = System.currentTimeMillis();
        if (scanState != ScanState.SCANNING || isAnalyzing || now - lastAnalysisAt < 900) {
            imageProxy.close();
            return;
        }
        if (imageProxy.getImage() == null) {
            imageProxy.close();
            return;
        }

        lastAnalysisAt = now;
        isAnalyzing = true;
        int rotation = imageProxy.getImageInfo().getRotationDegrees();
        int imageWidth = rotation == 90 || rotation == 270 ? imageProxy.getHeight() : imageProxy.getWidth();
        int imageHeight = rotation == 90 || rotation == 270 ? imageProxy.getWidth() : imageProxy.getHeight();
        InputImage image = InputImage.fromMediaImage(imageProxy.getImage(), rotation);
        recognizer.process(image)
                .addOnSuccessListener(result -> {
                    String text = filterTextInFrame(result, imageWidth, imageHeight).trim();
                    if (!text.equals(liveText)) {
                        liveText = text;
                        updateLiveResult(text);
                    }
                })
                .addOnCompleteListener(task -> {
                    isAnalyzing = false;
                    imageProxy.close();
                });
    }

    private String filterTextInFrame(Text result, int imageWidth, int imageHeight) {
        if (previewView == null || frameView == null || previewView.getWidth() == 0 || previewView.getHeight() == 0) {
            return result.getText() == null ? "" : result.getText();
        }

        RectF frame = frameView.getFrameRect();
        float viewWidth = previewView.getWidth();
        float viewHeight = previewView.getHeight();
        float scale = Math.min(viewWidth / imageWidth, viewHeight / imageHeight);
        float offsetX = (viewWidth - imageWidth * scale) / 2f;
        float offsetY = (viewHeight - imageHeight * scale) / 2f;

        StringBuilder builder = new StringBuilder();
        for (Text.TextBlock block : result.getTextBlocks()) {
            for (Text.Line line : block.getLines()) {
                Rect box = line.getBoundingBox();
                if (box == null) {
                    continue;
                }

                float centerX = box.centerX() * scale + offsetX;
                float centerY = box.centerY() * scale + offsetY;
                if (frame.contains(centerX, centerY)) {
                    if (builder.length() > 0) {
                        builder.append('\n');
                    }
                    builder.append(line.getText());
                }
            }
        }

        return builder.length() == 0 && frame.width() > viewWidth * 0.72f
                ? (result.getText() == null ? "" : result.getText())
                : builder.toString();
    }

    private void updateLiveResult(String text) {
        runOnUiThread(() -> {
            if (scanState != ScanState.SCANNING) {
                return;
            }
            resultTextView.setText(text);
            resultTextView.setTextIsSelectable(false);
            resultCard.setVisibility(text.isEmpty() ? View.GONE : View.VISIBLE);
        });
    }

    private void lockText() {
        String text = liveText == null ? "" : liveText.trim();
        if (text.isEmpty()) {
            hintTextView.setText("先对准有文字的书页");
            return;
        }

        scanState = ScanState.LOCKED;
        lockedText = text;
        savedInLockSession = 0;
        resultTextView.setText(lockedText);
        resultTextView.setTextIsSelectable(true);
        resultCard.setVisibility(View.VISIBLE);
        ((View) resultCard.getTag()).setVisibility(View.VISIBLE);
        primaryButton.setText("重新扫描");
        hintTextView.setText("文字已锁定，可慢慢选取摘录");
    }

    private void saveLockedText() {
        if (scanState != ScanState.LOCKED) {
            return;
        }
        String selected = selectedText();
        if (selected.isEmpty() && savedInLockSession > 0) {
            Toast.makeText(this, "请选择下一段文字", Toast.LENGTH_SHORT).show();
            hintTextView.setText("请选择下一段文字再保存");
            return;
        }

        String text = selected.isEmpty() ? lockedText : selected;
        if (text.trim().isEmpty()) {
            return;
        }
        quoteStore.add(text);
        savedInLockSession += 1;
        clearSelection();
        hintTextView.setText("已保存 " + savedInLockSession + " 条，可继续选择下一段");
        Toast.makeText(this, "已保存 " + savedInLockSession + " 条", Toast.LENGTH_SHORT).show();
    }

    private void copyLockedText() {
        if (scanState != ScanState.LOCKED) {
            return;
        }
        String selected = selectedText();
        copyToClipboard(selected.isEmpty() ? lockedText : selected);
        resetScan();
        Toast.makeText(this, "已复制，继续扫描", Toast.LENGTH_SHORT).show();
    }

    private String selectedText() {
        CharSequence text = resultTextView.getText();
        if (!(text instanceof Spannable)) {
            return "";
        }
        int start = Selection.getSelectionStart(text);
        int end = Selection.getSelectionEnd(text);
        if (start < 0 || end < 0 || start == end) {
            return "";
        }
        int from = Math.min(start, end);
        int to = Math.max(start, end);
        return text.subSequence(from, to).toString().trim();
    }

    private void clearSelection() {
        CharSequence text = resultTextView.getText();
        if (text instanceof Spannable) {
            Selection.removeSelection((Spannable) text);
        }
    }

    private void resetScan() {
        scanState = ScanState.SCANNING;
        liveText = "";
        lockedText = "";
        savedInLockSession = 0;
        resultTextView.setText("");
        resultTextView.setTextIsSelectable(false);
        resultCard.setVisibility(View.GONE);
        ((View) resultCard.getTag()).setVisibility(View.GONE);
        primaryButton.setText("锁定文字");
        hintTextView.setText("拖动或双指缩放取景框");
    }

    private void showList() {
        currentScreen = Screen.LIST;
        if (cameraProvider != null) {
            cameraProvider.unbindAll();
        }

        root = new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(247, 247, 250));
        setContentView(root);

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(18), dp(42), dp(18), dp(86));
        root.addView(page, matchParent());

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = new TextView(this);
        title.setText("轻摘");
        title.setTextSize(30);
        title.setTypeface(null, 1);
        title.setTextColor(Color.rgb(20, 20, 24));
        header.addView(title, new LinearLayout.LayoutParams(0, wrap(), 1f));

        Button copyAll = compactButton("复制全部");
        Button export = compactButton("导出 TXT");
        copyAll.setOnClickListener(v -> copyAllQuotes());
        export.setOnClickListener(v -> exportTxt());
        header.addView(copyAll);
        header.addView(export);
        page.addView(header, new LinearLayout.LayoutParams(match(), dp(58)));

        ScrollView scrollView = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scrollView.addView(list, new ScrollView.LayoutParams(match(), wrap()));
        page.addView(scrollView, new LinearLayout.LayoutParams(match(), 0, 1f));

        List<Quote> quotes = quoteStore.getAll();
        if (quotes.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText("暂无摘录\n扫描书页，保存喜欢的句子");
            empty.setTextColor(Color.rgb(112, 112, 118));
            empty.setTextSize(17);
            empty.setGravity(Gravity.CENTER);
            list.addView(empty, new LinearLayout.LayoutParams(match(), dp(420)));
        } else {
            for (Quote quote : quotes) {
                list.addView(rowView(quote));
            }
        }

        buildBottomBar();
    }

    private View rowView(Quote quote) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(16), dp(14), dp(16), dp(14));
        row.setBackground(rounded(Color.WHITE, dp(10)));
        row.setOnClickListener(v -> showDetail(quote));

        TextView preview = new TextView(this);
        preview.setText(quote.preview());
        preview.setTextColor(Color.rgb(25, 25, 29));
        preview.setTextSize(16);
        preview.setMaxLines(4);
        row.addView(preview);

        LinearLayout meta = new LinearLayout(this);
        meta.setGravity(Gravity.CENTER_VERTICAL);
        TextView time = new TextView(this);
        time.setText(quote.formattedTime());
        time.setTextColor(Color.rgb(130, 130, 138));
        time.setTextSize(13);
        meta.addView(time, new LinearLayout.LayoutParams(0, wrap(), 1f));

        Button copy = compactButton("复制");
        Button delete = compactButton("删除");
        copy.setOnClickListener(v -> {
            copyToClipboard(quote.text);
            Toast.makeText(this, "已复制", Toast.LENGTH_SHORT).show();
        });
        delete.setOnClickListener(v -> {
            quoteStore.delete(quote.id);
            showList();
        });
        meta.addView(copy);
        meta.addView(delete);
        row.addView(meta);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(match(), wrap());
        params.setMargins(0, dp(8), 0, dp(8));
        row.setLayoutParams(params);
        return row;
    }

    private void showDetail(Quote quote) {
        currentScreen = Screen.DETAIL;
        root = new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(247, 247, 250));
        setContentView(root);

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(18), dp(40), dp(18), dp(24));
        root.addView(page, matchParent());

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        Button back = compactButton("返回");
        back.setOnClickListener(v -> showList());
        TextView title = new TextView(this);
        title.setText("摘录详情");
        title.setGravity(Gravity.CENTER);
        title.setTextSize(22);
        title.setTypeface(null, 1);
        Button copy = compactButton("复制");
        header.addView(back, new LinearLayout.LayoutParams(dp(84), dp(44)));
        header.addView(title, new LinearLayout.LayoutParams(0, dp(44), 1f));
        header.addView(copy, new LinearLayout.LayoutParams(dp(84), dp(44)));
        page.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        TextView text = new TextView(this);
        text.setText(quote.text);
        text.setTextIsSelectable(true);
        text.setTextSize(18);
        text.setLineSpacing(dp(4), 1.0f);
        text.setTextColor(Color.rgb(20, 20, 24));
        text.setPadding(dp(18), dp(18), dp(18), dp(18));
        text.setBackground(rounded(Color.WHITE, dp(10)));
        scroll.addView(text, new ScrollView.LayoutParams(match(), wrap()));
        page.addView(scroll, new LinearLayout.LayoutParams(match(), 0, 1f));

        copy.setOnClickListener(v -> {
            CharSequence content = text.getText();
            String selected = "";
            if (content instanceof Spannable) {
                int start = Selection.getSelectionStart(content);
                int end = Selection.getSelectionEnd(content);
                if (start >= 0 && end >= 0 && start != end) {
                    selected = content.subSequence(Math.min(start, end), Math.max(start, end)).toString();
                }
            }
            copyToClipboard(selected.trim().isEmpty() ? quote.text : selected);
            Toast.makeText(this, "已复制", Toast.LENGTH_SHORT).show();
        });
    }

    private void copyAllQuotes() {
        String text = quoteStore.exportText();
        if (text.trim().isEmpty()) {
            Toast.makeText(this, "暂无摘录", Toast.LENGTH_SHORT).show();
            return;
        }
        copyToClipboard(text);
        Toast.makeText(this, "已复制全部", Toast.LENGTH_SHORT).show();
    }

    private void exportTxt() {
        try {
            String text = quoteStore.exportText();
            if (text.trim().isEmpty()) {
                Toast.makeText(this, "暂无摘录", Toast.LENGTH_SHORT).show();
                return;
            }
            File dir = new File(getCacheDir(), "exports");
            if (!dir.exists()) {
                dir.mkdirs();
            }
            String name = "Jelly-摘录-" + new SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).format(new Date()) + ".txt";
            File file = new File(dir, name);
            try (FileOutputStream output = new FileOutputStream(file)) {
                output.write(text.getBytes(StandardCharsets.UTF_8));
            }
            Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".fileprovider", file);
            Intent intent = new Intent(Intent.ACTION_SEND);
            intent.setType("text/plain");
            intent.putExtra(Intent.EXTRA_STREAM, uri);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(Intent.createChooser(intent, "导出 TXT"));
        } catch (Exception error) {
            Toast.makeText(this, "导出失败", Toast.LENGTH_SHORT).show();
        }
    }

    private void copyToClipboard(String text) {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("Jelly 摘录", text));
    }

    private void showPermissionMessage() {
        root.removeAllViews();
        TextView message = new TextView(this);
        message.setText("需要相机权限才能扫描书页\n请在系统设置中允许 Jelly 使用相机");
        message.setTextColor(Color.WHITE);
        message.setTextSize(18);
        message.setGravity(Gravity.CENTER);
        root.addView(message, matchParent());
    }

    private Button tabButton(String text, boolean selected) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextSize(15);
        button.setTextColor(selected ? Color.rgb(242, 163, 58) : Color.rgb(40, 40, 45));
        button.setBackgroundColor(Color.TRANSPARENT);
        return button;
    }

    private Button actionButton(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setAllCaps(false);
        button.setTextColor(Color.WHITE);
        button.setTypeface(null, 1);
        button.setBackground(rounded(Color.rgb(242, 163, 58), dp(12)));
        return button;
    }

    private Button compactButton(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setAllCaps(false);
        button.setTextSize(14);
        button.setTextColor(Color.rgb(242, 143, 34));
        button.setBackgroundColor(Color.TRANSPARENT);
        return button;
    }

    private TextView pillText(String text, int textColor, int backgroundColor) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(textColor);
        view.setTextSize(13);
        view.setTypeface(null, 1);
        view.setGravity(Gravity.CENTER);
        view.setPadding(dp(13), dp(8), dp(13), dp(8));
        view.setBackground(rounded(backgroundColor, dp(9)));
        return view;
    }

    private android.graphics.drawable.GradientDrawable rounded(int color, float radius) {
        android.graphics.drawable.GradientDrawable drawable = new android.graphics.drawable.GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radius);
        return drawable;
    }

    private FrameLayout.LayoutParams matchParent() {
        return new FrameLayout.LayoutParams(match(), match());
    }

    private LinearLayout.LayoutParams weightButton() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, match(), 1f);
        params.setMargins(dp(4), 0, dp(4), 0);
        return params;
    }

    private int match() {
        return ViewGroup.LayoutParams.MATCH_PARENT;
    }

    private int wrap() {
        return ViewGroup.LayoutParams.WRAP_CONTENT;
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
