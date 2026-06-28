#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>

#include "main/php.h"
#include "sapi/embed/php_embed.h"

#define TAG "TrueAsyncPHP"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* ------------------------------------------------------------------ */
/* Output capture                                                       */
/* ------------------------------------------------------------------ */

typedef struct { char *buf; size_t len, cap; } out_buf_t;
static out_buf_t g_out;

static void out_reset(void) {
    g_out.len = 0;
    if (!g_out.buf) {
        g_out.cap = 4096;
        g_out.buf = malloc(g_out.cap);
    }
    if (g_out.buf) g_out.buf[0] = '\0';
}

static size_t php_ub_write(const char *str, size_t len) {
    if (g_out.len + len + 1 > g_out.cap) {
        g_out.cap = (g_out.len + len + 1) * 2;
        g_out.buf = realloc(g_out.buf, g_out.cap);
        if (!g_out.buf) return 0;
    }
    memcpy(g_out.buf + g_out.len, str, len);
    g_out.len += len;
    g_out.buf[g_out.len] = '\0';
    return len;
}

static void php_log_message(const char *msg, int syslog_type) {
    LOGD("%s", msg);
}

/* ------------------------------------------------------------------ */
/* JNI exports                                                          */
/* ------------------------------------------------------------------ */

JNIEXPORT jstring JNICALL
Java_com_trueasync_demo_PhpBridge_eval(JNIEnv *env, jclass cls, jstring jcode) {
    const char *code = (*env)->GetStringUTFChars(env, jcode, NULL);
    if (!code) return (*env)->NewStringUTF(env, "");

    out_reset();

    php_embed_module.ub_write       = php_ub_write;
    php_embed_module.log_message    = php_log_message;
    php_embed_module.php_ini_ignore = 1;

    char *argv[] = {"php"};
    int   argc   = 1;

    PHP_EMBED_START_BLOCK(argc, argv)
        zend_eval_string((char *)code, NULL, "trueasync-demo");
    PHP_EMBED_END_BLOCK()

    (*env)->ReleaseStringUTFChars(env, jcode, code);
    return (*env)->NewStringUTF(env, g_out.buf ? g_out.buf : "");
}

JNIEXPORT jstring JNICALL
Java_com_trueasync_demo_PhpBridge_version(JNIEnv *env, jclass cls) {
    return (*env)->NewStringUTF(env, PHP_VERSION);
}
