/**
 * 例外の型とスタック位置だけをログ用に抽出し、例外メッセージの機密値混入を避ける。
 */
package com.example.dailyreport.observability;

public final class ExceptionLog {
    private static final int MAX_FRAMES_PER_CAUSE = 32;
    private static final int MAX_LENGTH = 4000;

    private ExceptionLog() {
    }

    public static String type(Throwable exception) {
        return exception.getClass().getName();
    }

    public static String stack(Throwable exception) {
        StringBuilder result = new StringBuilder();
        Throwable current = exception;
        while (current != null && result.length() < MAX_LENGTH) {
            if (result.length() > 0) {
                result.append(" | cause=");
            }
            result.append(current.getClass().getName());
            StackTraceElement[] frames = current.getStackTrace();
            int frameCount = Math.min(frames.length, MAX_FRAMES_PER_CAUSE);
            for (int index = 0; index < frameCount && result.length() < MAX_LENGTH; index++) {
                result.append(" at ").append(frames[index]);
            }
            current = current.getCause();
        }
        return result.length() > MAX_LENGTH ? result.substring(0, MAX_LENGTH) : result.toString();
    }
}
