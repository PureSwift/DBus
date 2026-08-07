/*
 * smoke.c
 * DBus
 *
 * A C program linked against the built `libdbus-swift.so`, exercising the
 * ABI the way a consumer would.
 *
 * This is not a duplicate of the SwiftPM suite. It covers two things that
 * suite structurally cannot:
 *
 *   - the variadic entry points (`dbus_message_append_args` and
 *     `dbus_message_get_args`), because Swift cannot call a C variadic
 *     function at all;
 *   - that the shared object actually links and loads, with every symbol a
 *     caller needs resolvable from outside.
 *
 * Nothing here touches a bus, so it runs anywhere.
 */

#include <dbus/dbus.h>

#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition)                                                     \
    do {                                                                     \
        if (!(condition)) {                                                  \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__,          \
                    #condition);                                             \
            failures++;                                                      \
        }                                                                    \
    } while (0)

static void test_error(void)
{
    DBusError error;
    dbus_error_init(&error);

    CHECK(!dbus_error_is_set(&error));

    dbus_set_error_const(&error, DBUS_ERROR_FAILED, "constant");
    CHECK(dbus_error_is_set(&error));
    CHECK(dbus_error_has_name(&error, DBUS_ERROR_FAILED));
    CHECK(strcmp(error.message, "constant") == 0);

    dbus_error_free(&error);
    CHECK(!dbus_error_is_set(&error));

    /* The variadic formatter. */
    dbus_set_error(&error, DBUS_ERROR_INVALID_ARGS, "expected %d, got %s", 42, "seven");
    CHECK(dbus_error_is_set(&error));
    CHECK(strcmp(error.message, "expected 42, got seven") == 0);

    /* Moving hands ownership over and clears the source. */
    DBusError destination;
    dbus_error_init(&destination);
    dbus_move_error(&error, &destination);

    CHECK(!dbus_error_is_set(&error));
    CHECK(dbus_error_has_name(&destination, DBUS_ERROR_INVALID_ARGS));

    dbus_error_free(&destination);
}

static void test_message_headers(void)
{
    DBusMessage *message = dbus_message_new_method_call("org.freedesktop.DBus",
                                                       "/org/freedesktop/DBus",
                                                       "org.freedesktop.DBus",
                                                       "ListNames");
    CHECK(message != NULL);
    if (message == NULL) {
        return;
    }

    CHECK(dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_METHOD_CALL);
    CHECK(dbus_message_is_method_call(message, "org.freedesktop.DBus", "ListNames"));
    CHECK(dbus_message_has_path(message, "/org/freedesktop/DBus"));
    CHECK(strcmp(dbus_message_get_member(message), "ListNames") == 0);

    dbus_message_unref(message);

    /* A malformed field yields NULL rather than a broken message. */
    CHECK(dbus_message_new_method_call(NULL, "bad path", NULL, "Method") == NULL);
}

static void test_append_and_get_args(void)
{
    DBusMessage *message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_CALL);
    CHECK(message != NULL);
    if (message == NULL) {
        return;
    }

    dbus_int32_t number = 1234;
    const char *text = "variadic";
    double fraction = 0.5;

    CHECK(dbus_message_append_args(message,
                                   DBUS_TYPE_INT32, &number,
                                   DBUS_TYPE_STRING, &text,
                                   DBUS_TYPE_DOUBLE, &fraction,
                                   DBUS_TYPE_INVALID));

    CHECK(strcmp(dbus_message_get_signature(message), "isd") == 0);

    DBusError error;
    dbus_error_init(&error);

    dbus_int32_t readNumber = 0;
    const char *readText = NULL;
    double readFraction = 0;

    CHECK(dbus_message_get_args(message, &error,
                                DBUS_TYPE_INT32, &readNumber,
                                DBUS_TYPE_STRING, &readText,
                                DBUS_TYPE_DOUBLE, &readFraction,
                                DBUS_TYPE_INVALID));

    CHECK(!dbus_error_is_set(&error));
    CHECK(readNumber == 1234);
    CHECK(readText != NULL && strcmp(readText, "variadic") == 0);
    CHECK(readFraction == 0.5);

    dbus_error_free(&error);

    /* Asking for the wrong type must fail and say so. */
    const char *wrong = NULL;
    CHECK(!dbus_message_get_args(message, &error,
                                 DBUS_TYPE_STRING, &wrong,
                                 DBUS_TYPE_INVALID));
    CHECK(dbus_error_is_set(&error));
    dbus_error_free(&error);

    dbus_message_unref(message);
}

static void test_string_array_args(void)
{
    DBusMessage *message = dbus_message_new(DBUS_MESSAGE_TYPE_METHOD_RETURN);
    CHECK(message != NULL);
    if (message == NULL) {
        return;
    }

    const char *values[] = { "alpha", "beta", "gamma" };
    const char **pointer = values;

    CHECK(dbus_message_append_args(message,
                                   DBUS_TYPE_ARRAY, DBUS_TYPE_STRING, &pointer, 3,
                                   DBUS_TYPE_INVALID));

    CHECK(strcmp(dbus_message_get_signature(message), "as") == 0);

    DBusError error;
    dbus_error_init(&error);

    char **read = NULL;
    int count = 0;

    CHECK(dbus_message_get_args(message, &error,
                                DBUS_TYPE_ARRAY, DBUS_TYPE_STRING, &read, &count,
                                DBUS_TYPE_INVALID));

    CHECK(!dbus_error_is_set(&error));
    CHECK(count == 3);

    if (read != NULL && count == 3) {
        CHECK(strcmp(read[0], "alpha") == 0);
        CHECK(strcmp(read[1], "beta") == 0);
        CHECK(strcmp(read[2], "gamma") == 0);
        CHECK(read[3] == NULL);
    }

    dbus_free_string_array(read);
    dbus_error_free(&error);
    dbus_message_unref(message);
}

static void test_iterators(void)
{
    DBusMessage *message = dbus_message_new(DBUS_MESSAGE_TYPE_SIGNAL);
    CHECK(message != NULL);
    if (message == NULL) {
        return;
    }

    /* Build `a{sv}` by hand, the shape org.freedesktop.DBus.Properties uses. */
    DBusMessageIter iter;
    dbus_message_iter_init_append(message, &iter);

    DBusMessageIter dictionary;
    CHECK(dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dictionary));

    DBusMessageIter entry;
    CHECK(dbus_message_iter_open_container(&dictionary, DBUS_TYPE_DICT_ENTRY, NULL, &entry));

    const char *key = "Volume";
    CHECK(dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key));

    DBusMessageIter variant;
    CHECK(dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "u", &variant));
    dbus_uint32_t volume = 11;
    CHECK(dbus_message_iter_append_basic(&variant, DBUS_TYPE_UINT32, &volume));
    CHECK(dbus_message_iter_close_container(&entry, &variant));

    CHECK(dbus_message_iter_close_container(&dictionary, &entry));
    CHECK(dbus_message_iter_close_container(&iter, &dictionary));

    CHECK(strcmp(dbus_message_get_signature(message), "a{sv}") == 0);

    /* Read it back. */
    DBusMessageIter reader;
    CHECK(dbus_message_iter_init(message, &reader));
    CHECK(dbus_message_iter_get_arg_type(&reader) == DBUS_TYPE_ARRAY);
    CHECK(dbus_message_iter_get_element_type(&reader) == DBUS_TYPE_DICT_ENTRY);

    DBusMessageIter entries;
    dbus_message_iter_recurse(&reader, &entries);
    CHECK(dbus_message_iter_get_arg_type(&entries) == DBUS_TYPE_DICT_ENTRY);

    DBusMessageIter pair;
    dbus_message_iter_recurse(&entries, &pair);

    const char *readKey = NULL;
    dbus_message_iter_get_basic(&pair, &readKey);
    CHECK(readKey != NULL && strcmp(readKey, "Volume") == 0);

    CHECK(dbus_message_iter_next(&pair));
    CHECK(dbus_message_iter_get_arg_type(&pair) == DBUS_TYPE_VARIANT);

    DBusMessageIter contained;
    dbus_message_iter_recurse(&pair, &contained);
    CHECK(dbus_message_iter_get_arg_type(&contained) == DBUS_TYPE_UINT32);

    dbus_uint32_t readVolume = 0;
    dbus_message_iter_get_basic(&contained, &readVolume);
    CHECK(readVolume == 11);

    dbus_message_unref(message);
}

static void test_memory(void)
{
    CHECK(dbus_threads_init_default());

    void *block = dbus_malloc(64);
    CHECK(block != NULL);
    dbus_free(block);

    unsigned char *zeroed = dbus_malloc0(16);
    CHECK(zeroed != NULL);
    if (zeroed != NULL) {
        for (int index = 0; index < 16; index++) {
            CHECK(zeroed[index] == 0);
        }
    }
    dbus_free(zeroed);

    /* A zero byte request yields NULL, and freeing NULL is valid. */
    CHECK(dbus_malloc(0) == NULL);
    dbus_free(NULL);
}

int main(void)
{
    test_error();
    test_message_headers();
    test_append_and_get_args();
    test_string_array_args();
    test_iterators();
    test_memory();

    if (failures == 0) {
        printf("C ABI smoke test: all checks passed\n");
        return 0;
    }

    fprintf(stderr, "C ABI smoke test: %d check(s) failed\n", failures);
    return 1;
}
