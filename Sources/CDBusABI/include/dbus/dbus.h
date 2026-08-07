/*
 * dbus.h
 * DBus
 *
 * The subset of the libdbus-1 C ABI implemented in Swift by this package.
 *
 * These declarations are written to be ABI compatible with the reference
 * libdbus-1, not copied from it: `DBusError` and `DBusMessageIter` reproduce
 * the reference layouts exactly, because callers allocate both on the stack,
 * and the integer constants reproduce the reference values. A program that
 * uses only the entry points declared here can link against this library
 * instead of libdbus-1 without being recompiled.
 *
 * What is deliberately absent
 * ---------------------------
 * The main loop integration -- `dbus_connection_set_watch_functions`,
 * `dbus_connection_set_timeout_functions`, `dbus_connection_dispatch`,
 * `dbus_connection_read_write*` and `DBusPendingCall` -- is not provided.
 * That API hands the caller raw pollable descriptors so it can drive I/O
 * from its own event loop. This implementation owns its I/O in a Swift
 * actor with its own read loop, so there is no descriptor to hand over and
 * no dispatch step to perform: exposing those functions would mean either
 * lying about what they do or reproducing an event loop that already
 * exists. Blocking calls, which is what most callers of that API end up
 * writing anyway, are fully supported.
 *
 * `cmake/symbols.txt` pins the exported symbol list, and
 * `Scripts/check-exports.sh` fails the build if the library exports
 * anything more or less than that list, so the boundary above is asserted
 * rather than described.
 */

#ifndef DBUS_H
#define DBUS_H

#include <stdarg.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Primitive types                                                     */
/* ------------------------------------------------------------------ */

typedef unsigned int  dbus_bool_t;
typedef unsigned int  dbus_unichar_t;
typedef signed short  dbus_int16_t;
typedef unsigned short dbus_uint16_t;
typedef signed int    dbus_int32_t;
typedef unsigned int  dbus_uint32_t;
typedef signed long long dbus_int64_t;
typedef unsigned long long dbus_uint64_t;

#define TRUE  1
#define FALSE 0

/* ------------------------------------------------------------------ */
/* Type codes                                                          */
/* ------------------------------------------------------------------ */

/*
 * Written as plain integers rather than the reference's `((int) 'y')`: the
 * value is what the ABI fixes, and a cast expression cannot be imported by
 * Swift, which needs these same constants.
 */
#define DBUS_TYPE_INVALID       0    /* '\0' */
#define DBUS_TYPE_BYTE          121  /* 'y' */
#define DBUS_TYPE_BOOLEAN       98   /* 'b' */
#define DBUS_TYPE_INT16         110  /* 'n' */
#define DBUS_TYPE_UINT16        113  /* 'q' */
#define DBUS_TYPE_INT32         105  /* 'i' */
#define DBUS_TYPE_UINT32        117  /* 'u' */
#define DBUS_TYPE_INT64         120  /* 'x' */
#define DBUS_TYPE_UINT64        116  /* 't' */
#define DBUS_TYPE_DOUBLE        100  /* 'd' */
#define DBUS_TYPE_STRING        115  /* 's' */
#define DBUS_TYPE_OBJECT_PATH   111  /* 'o' */
#define DBUS_TYPE_SIGNATURE     103  /* 'g' */
#define DBUS_TYPE_UNIX_FD       104  /* 'h' */
#define DBUS_TYPE_ARRAY         97   /* 'a' */
#define DBUS_TYPE_VARIANT       118  /* 'v' */
#define DBUS_TYPE_STRUCT        114  /* 'r' */
#define DBUS_TYPE_DICT_ENTRY    101  /* 'e' */

#define DBUS_STRUCT_BEGIN_CHAR      40  /* '(' */
#define DBUS_STRUCT_END_CHAR        41  /* ')' */
#define DBUS_DICT_ENTRY_BEGIN_CHAR  123 /* '{' */
#define DBUS_DICT_ENTRY_END_CHAR    125 /* '}' */

/* ------------------------------------------------------------------ */
/* Message types                                                       */
/* ------------------------------------------------------------------ */

#define DBUS_MESSAGE_TYPE_INVALID       0
#define DBUS_MESSAGE_TYPE_METHOD_CALL   1
#define DBUS_MESSAGE_TYPE_METHOD_RETURN 2
#define DBUS_MESSAGE_TYPE_ERROR         3
#define DBUS_MESSAGE_TYPE_SIGNAL        4

/* ------------------------------------------------------------------ */
/* Timeouts                                                            */
/* ------------------------------------------------------------------ */

#define DBUS_TIMEOUT_INFINITE     0x7fffffff
#define DBUS_TIMEOUT_USE_DEFAULT  (-1)

/* ------------------------------------------------------------------ */
/* Well known names                                                    */
/* ------------------------------------------------------------------ */

#define DBUS_SERVICE_DBUS   "org.freedesktop.DBus"
#define DBUS_PATH_DBUS      "/org/freedesktop/DBus"
#define DBUS_INTERFACE_DBUS "org.freedesktop.DBus"

#define DBUS_INTERFACE_INTROSPECTABLE "org.freedesktop.DBus.Introspectable"
#define DBUS_INTERFACE_PROPERTIES     "org.freedesktop.DBus.Properties"
#define DBUS_INTERFACE_PEER           "org.freedesktop.DBus.Peer"

/* ------------------------------------------------------------------ */
/* Error names                                                         */
/* ------------------------------------------------------------------ */

#define DBUS_ERROR_FAILED                 "org.freedesktop.DBus.Error.Failed"
#define DBUS_ERROR_NO_MEMORY              "org.freedesktop.DBus.Error.NoMemory"
#define DBUS_ERROR_SERVICE_UNKNOWN        "org.freedesktop.DBus.Error.ServiceUnknown"
#define DBUS_ERROR_NAME_HAS_NO_OWNER      "org.freedesktop.DBus.Error.NameHasNoOwner"
#define DBUS_ERROR_NO_REPLY               "org.freedesktop.DBus.Error.NoReply"
#define DBUS_ERROR_IO_ERROR               "org.freedesktop.DBus.Error.IOError"
#define DBUS_ERROR_BAD_ADDRESS            "org.freedesktop.DBus.Error.BadAddress"
#define DBUS_ERROR_NOT_SUPPORTED          "org.freedesktop.DBus.Error.NotSupported"
#define DBUS_ERROR_LIMITS_EXCEEDED        "org.freedesktop.DBus.Error.LimitsExceeded"
#define DBUS_ERROR_ACCESS_DENIED          "org.freedesktop.DBus.Error.AccessDenied"
#define DBUS_ERROR_AUTH_FAILED            "org.freedesktop.DBus.Error.AuthFailed"
#define DBUS_ERROR_NO_SERVER              "org.freedesktop.DBus.Error.NoServer"
#define DBUS_ERROR_TIMEOUT                "org.freedesktop.DBus.Error.Timeout"
#define DBUS_ERROR_DISCONNECTED           "org.freedesktop.DBus.Error.Disconnected"
#define DBUS_ERROR_INVALID_ARGS           "org.freedesktop.DBus.Error.InvalidArgs"
#define DBUS_ERROR_UNKNOWN_METHOD         "org.freedesktop.DBus.Error.UnknownMethod"
#define DBUS_ERROR_UNKNOWN_OBJECT         "org.freedesktop.DBus.Error.UnknownObject"
#define DBUS_ERROR_UNKNOWN_INTERFACE      "org.freedesktop.DBus.Error.UnknownInterface"
#define DBUS_ERROR_UNKNOWN_PROPERTY       "org.freedesktop.DBus.Error.UnknownProperty"
#define DBUS_ERROR_PROPERTY_READ_ONLY     "org.freedesktop.DBus.Error.PropertyReadOnly"
#define DBUS_ERROR_INVALID_SIGNATURE      "org.freedesktop.DBus.Error.InvalidSignature"

/* ------------------------------------------------------------------ */
/* Name registration                                                   */
/* ------------------------------------------------------------------ */

#define DBUS_NAME_FLAG_ALLOW_REPLACEMENT 0x1
#define DBUS_NAME_FLAG_REPLACE_EXISTING  0x2
#define DBUS_NAME_FLAG_DO_NOT_QUEUE      0x4

#define DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER 1
#define DBUS_REQUEST_NAME_REPLY_IN_QUEUE      2
#define DBUS_REQUEST_NAME_REPLY_EXISTS        3
#define DBUS_REQUEST_NAME_REPLY_ALREADY_OWNER 4

#define DBUS_RELEASE_NAME_REPLY_RELEASED      1
#define DBUS_RELEASE_NAME_REPLY_NON_EXISTENT  2
#define DBUS_RELEASE_NAME_REPLY_NOT_OWNER     3

/* ------------------------------------------------------------------ */
/* Opaque objects                                                      */
/* ------------------------------------------------------------------ */

typedef struct DBusConnection DBusConnection;
typedef struct DBusMessage DBusMessage;

typedef enum {
    DBUS_BUS_SESSION,
    DBUS_BUS_SYSTEM,
    DBUS_BUS_STARTER
} DBusBusType;

/* ------------------------------------------------------------------ */
/* DBusError                                                           */
/* ------------------------------------------------------------------ */

/*
 * Layout copied from the reference so callers can allocate one on the
 * stack. `name` and `message` are the only fields a caller reads.
 */
typedef struct {
    const char *name;
    const char *message;

    unsigned int dummy1 : 1;
    unsigned int dummy2 : 1;
    unsigned int dummy3 : 1;
    unsigned int dummy4 : 1;
    unsigned int dummy5 : 1;

    void *padding1;
} DBusError;

void        dbus_error_init(DBusError *error);
void        dbus_error_free(DBusError *error);
dbus_bool_t dbus_error_is_set(const DBusError *error);
dbus_bool_t dbus_error_has_name(const DBusError *error, const char *name);
void        dbus_set_error_const(DBusError *error, const char *name, const char *message);
void        dbus_set_error(DBusError *error, const char *name, const char *format, ...);
void        dbus_move_error(DBusError *src, DBusError *dest);

/* ------------------------------------------------------------------ */
/* DBusMessageIter                                                     */
/* ------------------------------------------------------------------ */

/*
 * Layout copied from the reference, for the same reason as DBusError: it
 * is a stack value. The fields are opaque; this implementation stores its
 * own state in them and never exposes their meaning.
 *
 * As in the reference, an iterator is only valid while the message it was
 * created from is alive, and there is no function to release one.
 */
typedef struct {
    void *dummy1;
    void *dummy2;
    dbus_uint32_t dummy3;
    int dummy4;
    int dummy5;
    int dummy6;
    int dummy7;
    int dummy8;
    int dummy9;
    int dummy10;
    int dummy11;
    int pad1;
    void *pad2;
    void *pad3;
} DBusMessageIter;

/* ------------------------------------------------------------------ */
/* Memory                                                              */
/* ------------------------------------------------------------------ */

void *dbus_malloc(size_t bytes);
void *dbus_malloc0(size_t bytes);
void  dbus_free(void *memory);
void  dbus_free_string_array(char **string_array);
void  dbus_shutdown(void);

/*
 * Provided as a no-op returning TRUE. The reference needs an explicit
 * opt-in to thread safety; this implementation is thread safe by
 * construction, so there is nothing to initialize, and callers that
 * dutifully call it keep working.
 */
dbus_bool_t dbus_threads_init_default(void);

/* ------------------------------------------------------------------ */
/* Messages                                                            */
/* ------------------------------------------------------------------ */

DBusMessage *dbus_message_new(int message_type);
DBusMessage *dbus_message_new_method_call(const char *destination,
                                          const char *path,
                                          const char *interface,
                                          const char *method);
DBusMessage *dbus_message_new_method_return(DBusMessage *method_call);
DBusMessage *dbus_message_new_signal(const char *path,
                                     const char *interface,
                                     const char *name);
DBusMessage *dbus_message_new_error(DBusMessage *reply_to,
                                    const char *error_name,
                                    const char *error_message);

DBusMessage *dbus_message_ref(DBusMessage *message);
void         dbus_message_unref(DBusMessage *message);
DBusMessage *dbus_message_copy(const DBusMessage *message);

int         dbus_message_get_type(DBusMessage *message);
dbus_uint32_t dbus_message_get_serial(DBusMessage *message);
dbus_uint32_t dbus_message_get_reply_serial(DBusMessage *message);

dbus_bool_t dbus_message_set_path(DBusMessage *message, const char *path);
const char *dbus_message_get_path(DBusMessage *message);
dbus_bool_t dbus_message_set_interface(DBusMessage *message, const char *interface);
const char *dbus_message_get_interface(DBusMessage *message);
dbus_bool_t dbus_message_set_member(DBusMessage *message, const char *member);
const char *dbus_message_get_member(DBusMessage *message);
dbus_bool_t dbus_message_set_destination(DBusMessage *message, const char *destination);
const char *dbus_message_get_destination(DBusMessage *message);
dbus_bool_t dbus_message_set_sender(DBusMessage *message, const char *sender);
const char *dbus_message_get_sender(DBusMessage *message);
dbus_bool_t dbus_message_set_error_name(DBusMessage *message, const char *name);
const char *dbus_message_get_error_name(DBusMessage *message);
const char *dbus_message_get_signature(DBusMessage *message);

void        dbus_message_set_no_reply(DBusMessage *message, dbus_bool_t no_reply);
dbus_bool_t dbus_message_get_no_reply(DBusMessage *message);

dbus_bool_t dbus_message_is_method_call(DBusMessage *message,
                                        const char *interface,
                                        const char *method);
dbus_bool_t dbus_message_is_signal(DBusMessage *message,
                                   const char *interface,
                                   const char *signal_name);
dbus_bool_t dbus_message_is_error(DBusMessage *message, const char *error_name);
dbus_bool_t dbus_message_has_path(DBusMessage *message, const char *path);
dbus_bool_t dbus_message_has_member(DBusMessage *message, const char *member);
dbus_bool_t dbus_message_has_interface(DBusMessage *message, const char *interface);
dbus_bool_t dbus_message_has_destination(DBusMessage *message, const char *name);
dbus_bool_t dbus_message_has_sender(DBusMessage *message, const char *name);

/* ------------------------------------------------------------------ */
/* Reading and writing arguments                                       */
/* ------------------------------------------------------------------ */

dbus_bool_t dbus_message_iter_init(DBusMessage *message, DBusMessageIter *iter);
dbus_bool_t dbus_message_iter_has_next(DBusMessageIter *iter);
dbus_bool_t dbus_message_iter_next(DBusMessageIter *iter);
int         dbus_message_iter_get_arg_type(DBusMessageIter *iter);
int         dbus_message_iter_get_element_type(DBusMessageIter *iter);
void        dbus_message_iter_recurse(DBusMessageIter *iter, DBusMessageIter *sub);
char       *dbus_message_iter_get_signature(DBusMessageIter *iter);
void        dbus_message_iter_get_basic(DBusMessageIter *iter, void *value);

void        dbus_message_iter_init_append(DBusMessage *message, DBusMessageIter *iter);
dbus_bool_t dbus_message_iter_append_basic(DBusMessageIter *iter, int type, const void *value);
dbus_bool_t dbus_message_iter_open_container(DBusMessageIter *iter,
                                             int type,
                                             const char *contained_signature,
                                             DBusMessageIter *sub);
dbus_bool_t dbus_message_iter_close_container(DBusMessageIter *iter, DBusMessageIter *sub);
void        dbus_message_iter_abandon_container(DBusMessageIter *iter, DBusMessageIter *sub);

/*
 * The variadic argument helpers. Both accept basic types, and arrays of a
 * basic type given as (DBUS_TYPE_ARRAY, element_type, &pointer, count) when
 * appending and (DBUS_TYPE_ARRAY, element_type, &pointer, &count) when
 * reading. Nested containers beyond that are expressible only through the
 * iterator functions above, exactly as in the reference.
 */
dbus_bool_t dbus_message_append_args(DBusMessage *message, int first_arg_type, ...);
dbus_bool_t dbus_message_append_args_valist(DBusMessage *message, int first_arg_type, va_list var_args);
dbus_bool_t dbus_message_get_args(DBusMessage *message, DBusError *error, int first_arg_type, ...);
dbus_bool_t dbus_message_get_args_valist(DBusMessage *message, DBusError *error, int first_arg_type, va_list var_args);

/* ------------------------------------------------------------------ */
/* Connections                                                         */
/* ------------------------------------------------------------------ */

DBusConnection *dbus_bus_get(DBusBusType type, DBusError *error);
DBusConnection *dbus_bus_get_private(DBusBusType type, DBusError *error);
DBusConnection *dbus_connection_open(const char *address, DBusError *error);
DBusConnection *dbus_connection_open_private(const char *address, DBusError *error);

DBusConnection *dbus_connection_ref(DBusConnection *connection);
void            dbus_connection_unref(DBusConnection *connection);
void            dbus_connection_close(DBusConnection *connection);

dbus_bool_t dbus_connection_get_is_connected(DBusConnection *connection);
dbus_bool_t dbus_connection_get_is_authenticated(DBusConnection *connection);
char       *dbus_connection_get_server_id(DBusConnection *connection);

dbus_bool_t  dbus_connection_send(DBusConnection *connection,
                                  DBusMessage *message,
                                  dbus_uint32_t *serial);
DBusMessage *dbus_connection_send_with_reply_and_block(DBusConnection *connection,
                                                       DBusMessage *message,
                                                       int timeout_milliseconds,
                                                       DBusError *error);
void         dbus_connection_flush(DBusConnection *connection);

/* ------------------------------------------------------------------ */
/* Bus operations                                                      */
/* ------------------------------------------------------------------ */

dbus_bool_t dbus_bus_register(DBusConnection *connection, DBusError *error);
const char *dbus_bus_get_unique_name(DBusConnection *connection);
char       *dbus_bus_get_id(DBusConnection *connection, DBusError *error);

int dbus_bus_request_name(DBusConnection *connection,
                          const char *name,
                          unsigned int flags,
                          DBusError *error);
int dbus_bus_release_name(DBusConnection *connection,
                          const char *name,
                          DBusError *error);

dbus_bool_t dbus_bus_name_has_owner(DBusConnection *connection,
                                    const char *name,
                                    DBusError *error);
dbus_bool_t dbus_bus_start_service_by_name(DBusConnection *connection,
                                           const char *name,
                                           dbus_uint32_t flags,
                                           dbus_uint32_t *result,
                                           DBusError *error);

void dbus_bus_add_match(DBusConnection *connection, const char *rule, DBusError *error);
void dbus_bus_remove_match(DBusConnection *connection, const char *rule, DBusError *error);

unsigned long dbus_bus_get_unix_user(DBusConnection *connection,
                                     const char *name,
                                     DBusError *error);

#ifdef __cplusplus
}
#endif

#endif /* DBUS_H */
