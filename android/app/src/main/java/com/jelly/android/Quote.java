package com.jelly.android;

import org.json.JSONException;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.UUID;

final class Quote {
    final String id;
    final String text;
    final long createdAt;

    Quote(String text) {
        this(UUID.randomUUID().toString(), text, System.currentTimeMillis());
    }

    Quote(String id, String text, long createdAt) {
        this.id = id;
        this.text = text == null ? "" : text.trim();
        this.createdAt = createdAt;
    }

    String preview() {
        if (text.length() <= 80) {
            return text;
        }
        return text.substring(0, 80) + "...";
    }

    String formattedTime() {
        return new SimpleDateFormat("HH:mm", Locale.CHINA).format(new Date(createdAt));
    }

    JSONObject toJson() throws JSONException {
        JSONObject object = new JSONObject();
        object.put("id", id);
        object.put("text", text);
        object.put("createdAt", createdAt);
        return object;
    }

    static Quote fromJson(JSONObject object) {
        return new Quote(
                object.optString("id", UUID.randomUUID().toString()),
                object.optString("text", ""),
                object.optLong("createdAt", System.currentTimeMillis())
        );
    }
}
