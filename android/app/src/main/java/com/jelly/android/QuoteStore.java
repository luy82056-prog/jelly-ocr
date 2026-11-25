package com.jelly.android;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;

import java.util.ArrayList;
import java.util.List;

final class QuoteStore {
    private static final String PREFS = "jelly_quotes";
    private static final String KEY_QUOTES = "quotes";

    private final SharedPreferences preferences;

    QuoteStore(Context context) {
        preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    List<Quote> getAll() {
        ArrayList<Quote> quotes = new ArrayList<>();
        String raw = preferences.getString(KEY_QUOTES, "[]");
        try {
            JSONArray array = new JSONArray(raw);
            for (int i = 0; i < array.length(); i++) {
                quotes.add(Quote.fromJson(array.getJSONObject(i)));
            }
        } catch (JSONException ignored) {
        }
        return quotes;
    }

    void add(String text) {
        String trimmed = text == null ? "" : text.trim();
        if (trimmed.isEmpty()) {
            return;
        }

        ArrayList<Quote> quotes = new ArrayList<>(getAll());
        quotes.add(0, new Quote(trimmed));
        save(quotes);
    }

    void delete(String id) {
        ArrayList<Quote> quotes = new ArrayList<>();
        for (Quote quote : getAll()) {
            if (!quote.id.equals(id)) {
                quotes.add(quote);
            }
        }
        save(quotes);
    }

    String exportText() {
        StringBuilder builder = new StringBuilder();
        List<Quote> quotes = getAll();
        for (int i = 0; i < quotes.size(); i++) {
            if (i > 0) {
                builder.append("\n\n");
            }
            builder.append(quotes.get(i).text);
        }
        return builder.toString();
    }

    private void save(List<Quote> quotes) {
        JSONArray array = new JSONArray();
        for (Quote quote : quotes) {
            try {
                array.put(quote.toJson());
            } catch (JSONException ignored) {
            }
        }
        preferences.edit().putString(KEY_QUOTES, array.toString()).apply();
    }
}
