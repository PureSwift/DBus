/*
 * varargs.c
 * DBus
 *
 * The variadic entry points of the libdbus-1 ABI.
 *
 * Swift cannot declare a C variadic function, so these four live in C and
 * are implemented entirely in terms of the iterator entry points, which are
 * Swift. There is no protocol logic here: this file walks a `va_list` and
 * makes the same calls a caller could have made by hand.
 */

#include "include/dbus/dbus.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* Implemented in Swift; sets an error from two NUL terminated strings. */
extern void _dbus_abi_set_error(DBusError *error, const char *name, const char *message);

void dbus_set_error(DBusError *error, const char *name, const char *format, ...)
{
    if (error == NULL) {
        return;
    }

    if (format == NULL) {
        _dbus_abi_set_error(error, name, "");
        return;
    }

    va_list args;
    va_start(args, format);

    va_list measure;
    va_copy(measure, args);
    int length = vsnprintf(NULL, 0, format, measure);
    va_end(measure);

    if (length < 0) {
        va_end(args);
        _dbus_abi_set_error(error, name, "");
        return;
    }

    char *buffer = malloc((size_t) length + 1);
    if (buffer == NULL) {
        va_end(args);
        _dbus_abi_set_error(error, DBUS_ERROR_NO_MEMORY, "Out of memory");
        return;
    }

    vsnprintf(buffer, (size_t) length + 1, format, args);
    va_end(args);

    _dbus_abi_set_error(error, name, buffer);
    free(buffer);
}

/* Whether a type code is a fixed size basic type passed by pointer. */
static int is_basic_type(int type)
{
    switch (type) {
    case DBUS_TYPE_BYTE:
    case DBUS_TYPE_BOOLEAN:
    case DBUS_TYPE_INT16:
    case DBUS_TYPE_UINT16:
    case DBUS_TYPE_INT32:
    case DBUS_TYPE_UINT32:
    case DBUS_TYPE_INT64:
    case DBUS_TYPE_UINT64:
    case DBUS_TYPE_DOUBLE:
    case DBUS_TYPE_UNIX_FD:
    case DBUS_TYPE_STRING:
    case DBUS_TYPE_OBJECT_PATH:
    case DBUS_TYPE_SIGNATURE:
        return 1;
    default:
        return 0;
    }
}

/* The width of one element of a fixed size array, for the array helpers. */
static size_t element_size(int type)
{
    switch (type) {
    case DBUS_TYPE_BYTE:
        return 1;
    case DBUS_TYPE_INT16:
    case DBUS_TYPE_UINT16:
        return 2;
    case DBUS_TYPE_BOOLEAN:
    case DBUS_TYPE_INT32:
    case DBUS_TYPE_UINT32:
    case DBUS_TYPE_UNIX_FD:
        return 4;
    case DBUS_TYPE_INT64:
    case DBUS_TYPE_UINT64:
    case DBUS_TYPE_DOUBLE:
        return 8;
    default:
        return 0;
    }
}

dbus_bool_t dbus_message_append_args_valist(DBusMessage *message,
                                            int first_arg_type,
                                            va_list var_args)
{
    if (message == NULL) {
        return FALSE;
    }

    DBusMessageIter iter;
    dbus_message_iter_init_append(message, &iter);

    int type = first_arg_type;

    while (type != DBUS_TYPE_INVALID) {

        if (is_basic_type(type)) {

            const void *value = va_arg(var_args, const void *);
            if (!dbus_message_iter_append_basic(&iter, type, value)) {
                return FALSE;
            }
        }
        else if (type == DBUS_TYPE_ARRAY) {

            int element = va_arg(var_args, int);
            /*
             * The reference takes the *address of* the array pointer here,
             * not the array itself, so this dereferences once to reach the
             * elements.
             */
            const void *const *arrayPointer = va_arg(var_args, const void *const *);
            int count = va_arg(var_args, int);

            const void *array = (arrayPointer != NULL) ? *arrayPointer : NULL;

            if (array == NULL && count > 0) {
                return FALSE;
            }

            char signature[2] = { (char) element, '\0' };

            DBusMessageIter sub;
            if (!dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, signature, &sub)) {
                return FALSE;
            }

            if (element == DBUS_TYPE_STRING ||
                element == DBUS_TYPE_OBJECT_PATH ||
                element == DBUS_TYPE_SIGNATURE) {

                /* An array of strings arrives as `const char **`. */
                const char *const *strings = (const char *const *) array;
                for (int index = 0; index < count; index++) {
                    const char *entry = strings[index];
                    if (!dbus_message_iter_append_basic(&sub, element, &entry)) {
                        dbus_message_iter_abandon_container(&iter, &sub);
                        return FALSE;
                    }
                }
            }
            else {

                size_t width = element_size(element);
                if (width == 0) {
                    dbus_message_iter_abandon_container(&iter, &sub);
                    return FALSE;
                }

                const unsigned char *bytes = (const unsigned char *) array;
                for (int index = 0; index < count; index++) {
                    if (!dbus_message_iter_append_basic(&sub, element, bytes + (size_t) index * width)) {
                        dbus_message_iter_abandon_container(&iter, &sub);
                        return FALSE;
                    }
                }
            }

            if (!dbus_message_iter_close_container(&iter, &sub)) {
                return FALSE;
            }
        }
        else {
            /* Nested containers are expressible only through the iterators. */
            return FALSE;
        }

        type = va_arg(var_args, int);
    }

    return TRUE;
}

dbus_bool_t dbus_message_append_args(DBusMessage *message, int first_arg_type, ...)
{
    va_list args;
    va_start(args, first_arg_type);
    dbus_bool_t result = dbus_message_append_args_valist(message, first_arg_type, args);
    va_end(args);
    return result;
}

dbus_bool_t dbus_message_get_args_valist(DBusMessage *message,
                                         DBusError *error,
                                         int first_arg_type,
                                         va_list var_args)
{
    if (message == NULL) {
        _dbus_abi_set_error(error, DBUS_ERROR_INVALID_ARGS, "No message");
        return FALSE;
    }

    DBusMessageIter iter;
    dbus_bool_t hasArguments = dbus_message_iter_init(message, &iter);

    int type = first_arg_type;

    while (type != DBUS_TYPE_INVALID) {

        if (!hasArguments) {
            _dbus_abi_set_error(error, DBUS_ERROR_INVALID_ARGS,
                                "Message has too few arguments");
            return FALSE;
        }

        int actual = dbus_message_iter_get_arg_type(&iter);

        if (type == DBUS_TYPE_ARRAY) {

            int element = va_arg(var_args, int);
            void *out = va_arg(var_args, void *);
            int *count = va_arg(var_args, int *);

            if (actual != DBUS_TYPE_ARRAY ||
                dbus_message_iter_get_element_type(&iter) != element) {
                _dbus_abi_set_error(error, DBUS_ERROR_INVALID_ARGS,
                                    "Message argument is not an array of the expected type");
                return FALSE;
            }

            if (element != DBUS_TYPE_STRING &&
                element != DBUS_TYPE_OBJECT_PATH &&
                element != DBUS_TYPE_SIGNATURE) {
                _dbus_abi_set_error(error, DBUS_ERROR_NOT_SUPPORTED,
                                    "Only arrays of strings can be read this way; "
                                    "use dbus_message_iter_recurse");
                return FALSE;
            }

            DBusMessageIter sub;
            dbus_message_iter_recurse(&iter, &sub);

            int capacity = 8;
            int length = 0;
            char **strings = malloc(sizeof(char *) * (size_t) capacity);
            if (strings == NULL) {
                _dbus_abi_set_error(error, DBUS_ERROR_NO_MEMORY, "Out of memory");
                return FALSE;
            }

            while (dbus_message_iter_get_arg_type(&sub) != DBUS_TYPE_INVALID) {

                const char *value = NULL;
                dbus_message_iter_get_basic(&sub, &value);

                if (length + 1 >= capacity) {
                    capacity *= 2;
                    char **grown = realloc(strings, sizeof(char *) * (size_t) capacity);
                    if (grown == NULL) {
                        dbus_free_string_array(strings);
                        _dbus_abi_set_error(error, DBUS_ERROR_NO_MEMORY, "Out of memory");
                        return FALSE;
                    }
                    strings = grown;
                }

                strings[length] = strdup(value != NULL ? value : "");
                if (strings[length] == NULL) {
                    strings[length] = NULL;
                    dbus_free_string_array(strings);
                    _dbus_abi_set_error(error, DBUS_ERROR_NO_MEMORY, "Out of memory");
                    return FALSE;
                }

                length++;
                dbus_message_iter_next(&sub);
            }

            strings[length] = NULL;

            *(char ***) out = strings;
            if (count != NULL) {
                *count = length;
            }
        }
        else if (is_basic_type(type)) {

            if (actual != type) {
                _dbus_abi_set_error(error, DBUS_ERROR_INVALID_ARGS,
                                    "Message argument is not of the expected type");
                return FALSE;
            }

            void *out = va_arg(var_args, void *);
            dbus_message_iter_get_basic(&iter, out);
        }
        else {
            _dbus_abi_set_error(error, DBUS_ERROR_NOT_SUPPORTED,
                                "Type is not readable this way; use dbus_message_iter_recurse");
            return FALSE;
        }

        hasArguments = dbus_message_iter_next(&iter);
        type = va_arg(var_args, int);
    }

    return TRUE;
}

dbus_bool_t dbus_message_get_args(DBusMessage *message, DBusError *error, int first_arg_type, ...)
{
    va_list args;
    va_start(args, first_arg_type);
    dbus_bool_t result = dbus_message_get_args_valist(message, error, first_arg_type, args);
    va_end(args);
    return result;
}
